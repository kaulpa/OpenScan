package com.ethereal.openscan;

import android.content.Context;
import android.graphics.Rect;
import android.net.Uri;
import android.os.Handler;
import android.os.Looper;

import androidx.annotation.NonNull;

import com.google.android.gms.tasks.Tasks;
import com.google.mlkit.vision.common.InputImage;
import com.google.mlkit.vision.text.Text;
import com.google.mlkit.vision.text.TextRecognition;
import com.google.mlkit.vision.text.TextRecognizer;
import com.google.mlkit.vision.text.latin.TextRecognizerOptions;

import java.io.File;
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
 * {@code text_recognition.dart}), so this only decodes and recognises:
 * {@code read} returns the text of a marked caption, {@code lines} every
 * line on a whole page with where it is.
 */
final class TextReader implements MethodChannel.MethodCallHandler {
    static final String CHANNEL = "openscan/text_reader";

    private final Context context;
    private final ExecutorService executor = Executors.newSingleThreadExecutor();
    private final Handler main = new Handler(Looper.getMainLooper());
    private TextRecognizer recognizer;

    TextReader(Context context) {
        this.context = context.getApplicationContext();
    }

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
        executor.execute(() -> {
            try {
                final InputImage image = InputImage.fromFilePath(context, Uri.fromFile(new File(path)));
                // On this executor, never the main thread, so it may block.
                final Text text = Tasks.await(recognizer().process(image));
                final Object recognised = lines ? linesOf(text) : text.getText();
                main.post(() -> result.success(recognised));
            } catch (Throwable t) {
                main.post(() -> result.error("read_failed", String.valueOf(t), null));
            }
        });
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
