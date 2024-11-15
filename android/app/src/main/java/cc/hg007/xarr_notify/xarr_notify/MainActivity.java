package cc.hg007.xarr_notify.xarr_notify;

import io.flutter.embedding.android.FlutterActivity;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.os.Build;
import android.os.Bundle;

public class MainActivity extends FlutterActivity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        createNotificationChannel();
    }

    private void createNotificationChannel() {
        // 仅在 Android 8.0 及以上版本中创建通知渠道
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            String channelId = "xarr_notify_channel"; // 确保这个 ID 与 Flutter 中使用的 ID 一致
            CharSequence name = "xarr通知"; // 渠道名称
            String description = "xarr通知"; // 渠道描述
            int importance = NotificationManager.IMPORTANCE_DEFAULT;

            NotificationChannel channel = new NotificationChannel(channelId, name, importance);
            channel.setDescription(description);

            // 注册渠道
            NotificationManager notificationManager = getSystemService(NotificationManager.class);
            notificationManager.createNotificationChannel(channel);
        }
    }
}
