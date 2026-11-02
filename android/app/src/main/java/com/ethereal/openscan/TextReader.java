package com.ethereal.openscan;

import android.content.Context;
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
 * The Dart side hands over a file that is already just the marked caption,
 * the right way up (see {@code text_recognition.dart}), so this only
 * decodes it and recognises.
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
        if (!"read".equals(call.method)) {
            result.notImplemented();
            return;
        }
        final String path = call.argument("path");
        executor.execute(() -> {
            try {
                final InputImage image = InputImage.fromFilePath(context, Uri.fromFile(new File(path)));
                // On this executor, never the main thread, so it may block.
                final Text text = Tasks.await(recognizer().process(image));
                final String recognised = text.getText();
                main.post(() -> result.success(recognised));
            } catch (Throwable t) {
                main.post(() -> result.error("read_failed", String.valueOf(t), null));
            }
        });
    }
}
