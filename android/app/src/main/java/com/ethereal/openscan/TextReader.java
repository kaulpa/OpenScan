package com.ethereal.openscan;

import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Matrix;
import android.graphics.Rect;
import android.os.Handler;
import android.os.Looper;

import androidx.annotation.NonNull;

import com.google.android.gms.tasks.Tasks;
import com.google.mlkit.vision.common.InputImage;
import com.google.mlkit.vision.text.Text;
import com.google.mlkit.vision.text.TextRecognition;
import com.google.mlkit.vision.text.TextRecognizer;
import com.google.mlkit.vision.text.latin.TextRecognizerOptions;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/**
 * Reads the text in an image file with ML Kit's on-device recognizer for
 * Latin script — German, French, Italian and English captions alike. The
 * model ships inside the app, so recognition works offline and the image
 * never leaves the phone.
 *
 * The Dart side hands over a file that is already the right way up (see
 * {@code text_recognition.dart}), so this decodes it, makes what is
 * written on it stand out ({@link #enhanced}) and recognises: {@code read}
 * returns the text of a marked caption, {@code lines} every line on a
 * whole page, turned {@code turns} quarter turns clockwise, with where it
 * is.
 */
final class TextReader implements MethodChannel.MethodCallHandler {
    static final String CHANNEL = "openscan/text_reader";

    private final ExecutorService executor = Executors.newSingleThreadExecutor();
    private final Handler main = new Handler(Looper.getMainLooper());
    private TextRecognizer recognizer;

    private synchronized TextRecognizer recognizer() {
        if (recognizer == null) {
            recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS);
        }
        return recognizer;
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        final boolean lines = "lines".equals(call.method);
        if (!lines && !"read".equals(call.method)) {
            result.notImplemented();
            return;
        }
        final String path = call.argument("path");
        final Integer turns = call.argument("turns");
        executor.execute(() -> {
            try {
                final Object recognised;
                if (lines) {
                    recognised = linesOf(recognise(turned(pageFor(path), turns == null ? 0 : turns)));
                } else {
                    final Bitmap photo = decode(path);
                    // Nothing made out after the stretch, which can break
                    // up writing already dark enough: the photo as it was.
                    final String found = recognise(enhanced(photo)).getText();
                    recognised = found.trim().isEmpty() ? recognise(photo).getText() : found;
                }
                main.post(() -> result.success(recognised));
            } catch (Throwable t) {
                main.post(() -> result.error("read_failed", String.valueOf(t), null));
            }
        });
    }

    /**
     * The page last looked for lines on, made ready ({@link #enhanced}): the
     * Dart side asks for the same page again turned a quarter either way
     * when it finds no caption on it as it is. Only touched on the executor.
     */
    private String pagePath;
    private Bitmap page;

    private Bitmap pageFor(String path) {
        if (!path.equals(pagePath)) {
            page = enhanced(decode(path));
            pagePath = path;
        }
        return page;
    }

    private static Bitmap decode(String path) {
        final Bitmap bitmap = BitmapFactory.decodeFile(path);
        if (bitmap == null) throw new IllegalStateException("could not decode " + path);
        return bitmap;
    }

    /** {@code bitmap} turned {@code turns} quarter turns clockwise. */
    private static Bitmap turned(Bitmap bitmap, int turns) {
        if (turns % 4 == 0) return bitmap;
        final Matrix matrix = new Matrix();
        matrix.postRotate(90f * turns);
        return Bitmap.createBitmap(bitmap, 0, 0, bitmap.getWidth(), bitmap.getHeight(), matrix, true);
    }

    /** On this executor, never the main thread, so it may block. */
    private Text recognise(Bitmap bitmap) throws Exception {
        return Tasks.await(recognizer().process(InputImage.fromBitmap(bitmap, 0)));
    }

    /**
     * Brightness relative to the paper round it at which a pixel counts as
     * written on, and is drawn black ({@link #enhanced}).
     */
    private static final float INKED = 0.84f;

    /** ... and at which it counts as paper, and is drawn white. */
    private static final float PAPER = 0.97f;

    /**
     * {@code src} as the recognizer reads best: the paper flattened to
     * white, whatever is written on it stretched to black, in grey. ML Kit
     * is trained on ink on paper; pencil on an album's cream card is at
     * most a few dozen grey levels darker than the card, under light that
     * falls off across the page, and it passes over it.
     *
     * The paper's brightness is taken as the brightest of each small patch
     * of the picture and its neighbours, smoothed — the writing is too thin
     * to fill a patch — and every pixel is measured against that.
     */
    static Bitmap enhanced(Bitmap src) {
        final int w = src.getWidth(), h = src.getHeight();
        final int[] px = new int[w * h];
        src.getPixels(px, 0, w, 0, 0, w, h);
        return Bitmap.createBitmap(enhance(px, w, h), w, h, Bitmap.Config.ARGB_8888);
    }

    /** {@link #enhanced} on ARGB pixels, {@code w} by {@code h}. */
    static int[] enhance(int[] px, int w, int h) {
        final float[] lum = new float[w * h];
        for (int i = 0; i < px.length; i++) {
            final int c = px[i];
            lum[i] = 0.299f * ((c >> 16) & 0xff) + 0.587f * ((c >> 8) & 0xff) + 0.114f * (c & 0xff);
        }
        // Against the card's grain, which the stretch would blow up too.
        final float[] soft = neighbourhood(lum, w, h, false);

        final int cell = Math.max(4, Math.round(Math.min(w, h) * 0.02f));
        final int gw = (w + cell - 1) / cell, gh = (h + cell - 1) / cell;
        float[] paper = new float[gw * gh];
        for (int y = 0; y < h; y++) {
            final int row = (y / cell) * gw;
            for (int x = 0; x < w; x++) {
                final int g = row + x / cell;
                final float v = soft[y * w + x];
                if (v > paper[g]) paper[g] = v;
            }
        }
        paper = neighbourhood(paper, gw, gh, true);
        paper = neighbourhood(paper, gw, gh, false);

        final int[] out = new int[w * h];
        for (int y = 0; y < h; y++) {
            final float fy = Math.max(0f, Math.min(gh - 1f, (y + 0.5f) / cell - 0.5f));
            final int y0 = (int) fy, y1 = Math.min(gh - 1, y0 + 1);
            final float ty = fy - y0;
            for (int x = 0; x < w; x++) {
                final float fx = Math.max(0f, Math.min(gw - 1f, (x + 0.5f) / cell - 0.5f));
                final int x0 = (int) fx, x1 = Math.min(gw - 1, x0 + 1);
                final float tx = fx - x0;
                final float here = (paper[y0 * gw + x0] * (1 - tx) + paper[y0 * gw + x1] * tx) * (1 - ty)
                        + (paper[y1 * gw + x0] * (1 - tx) + paper[y1 * gw + x1] * tx) * ty;
                final float flat = soft[y * w + x] / Math.max(here, 1f);
                final float v = Math.max(0f, Math.min(1f, (flat - INKED) / (PAPER - INKED)));
                final int g = Math.round(255 * v);
                out[y * w + x] = 0xff000000 | (g << 16) | (g << 8) | g;
            }
        }
        return out;
    }

    /** The brightest ({@code max}) or mean of each pixel's 3x3 neighbourhood. */
    private static float[] neighbourhood(float[] src, int w, int h, boolean max) {
        final float[] out = new float[w * h];
        for (int y = 0; y < h; y++) {
            for (int x = 0; x < w; x++) {
                float acc = 0f;
                int n = 0;
                for (int dy = -1; dy <= 1; dy++) {
                    final int yy = Math.max(0, Math.min(h - 1, y + dy));
                    for (int dx = -1; dx <= 1; dx++) {
                        final float v = src[yy * w + Math.max(0, Math.min(w - 1, x + dx))];
                        if (max) {
                            if (v > acc) acc = v;
                        } else {
                            acc += v;
                        }
                        n++;
                    }
                }
                out[y * w + x] = max ? acc : acc / n;
            }
        }
        return out;
    }

    /**
     * Every line found, with the box round it in the image's pixels and the
     * index of the block (paragraph) it belongs to: what the Dart side looks
     * for a photo's caption among.
     */
    private static List<Map<String, Object>> linesOf(Text text) {
        final List<Map<String, Object>> out = new ArrayList<>();
        final List<Text.TextBlock> blocks = text.getTextBlocks();
        for (int b = 0; b < blocks.size(); b++) {
            for (Text.Line line : blocks.get(b).getLines()) {
                final Rect box = line.getBoundingBox();
                if (box == null) continue;
                final Map<String, Object> m = new HashMap<>();
                m.put("text", line.getText());
                m.put("block", b);
                m.put("left", box.left);
                m.put("top", box.top);
                m.put("right", box.right);
                m.put("bottom", box.bottom);
                out.add(m);
            }
        }
        return out;
    }
}
