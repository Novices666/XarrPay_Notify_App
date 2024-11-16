import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_background/flutter_background.dart';
import 'package:permission_handler/permission_handler.dart';
import 'database_helper.dart'; // 确保此文件存在
import 'dart:async';
import 'dart:convert';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'xarr-notify',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: ConnectionPage(),
    );
  }
}

class ConnectionPage extends StatefulWidget {
  @override
  _ConnectionPageState createState() => _ConnectionPageState();
}

class _ConnectionPageState extends State<ConnectionPage> {
  final TextEditingController _domainController = TextEditingController();
  final TextEditingController _uidController = TextEditingController();
  final TextEditingController _keyController = TextEditingController();

  bool _isWSS = false;
  String _connectionStatus = "未连接";
  WebSocketChannel? channel;
  bool _isConnected = false; // 连接状态

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  // 加载用户偏好配置
  Future<void> _loadPreferences() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    _domainController.text = prefs.getString('domain') ?? '';
    _uidController.text = prefs.getString('uid') ?? '';
    _keyController.text = prefs.getString('key') ?? '';
    _isWSS = prefs.getBool('isWSS') ?? false;
    setState(() {});
  }

  // 保存用户偏好配置
  Future<void> _savePreferences() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('domain', _domainController.text);
    await prefs.setString('uid', _uidController.text);
    await prefs.setString('key', _keyController.text);
    await prefs.setBool('isWSS', _isWSS);
  }

  void _connect() {
    String protocol = _isWSS ? 'wss' : 'ws';
    String url = '$protocol://${_domainController.text}/api/ws?uid=${_uidController.text}&message_key=${_keyController.text}';

    _savePreferences();

    channel = WebSocketChannel.connect(Uri.parse(url));
    channel?.stream.listen(
      (data) {
        _handleMessage(data);
      },
      onError: (error) {
        String errorMessage;
        if (error is WebSocketChannelException) {
          // 尝试获取更详细的信息
          errorMessage = error.message ?? '无法连接到服务器';
        } else if (error is Exception) {
          errorMessage = '发生未知错误: ${error.toString()}';
        } else {
          errorMessage = '未知错误类型';
        }

        _showConnectionError('连接失败', errorMessage); // 显示具体错误信息
        setState(() {
          _connectionStatus = '未连接';
          _isConnected = false;
        });
      },
      onDone: () {
        setState(() {
          _connectionStatus = '未连接';
          _isConnected = false;
        });
      },
    );

    setState(() {
      _connectionStatus = '已连接';
      _isConnected = true;
    });

    startBackgroundService(); // 启动后台服务
  }

  // 显示连接错误
  void _showConnectionError(String title, String message) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message), // 显示错误信息
          actions: [
            TextButton(
              child: const Text('关闭',style: TextStyle(color: Colors.blue)),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }




  // 启动后台服务
  Future<void> startBackgroundService() async {
    await _requestPermissions(); // 请求权限

    var androidConfig = const FlutterBackgroundAndroidConfig(
      notificationTitle: "后台服务",
      notificationText: "该服务在后台运行。",
      notificationImportance: AndroidNotificationImportance.normal,
      notificationIcon: AndroidResource(name: 'ic_launcher', defType: 'mipmap'),
      enableWifiLock: true,
      showBadge: true,
      shouldRequestBatteryOptimizationsOff: true,
    );

    await FlutterBackground.initialize(androidConfig: androidConfig);
    await FlutterBackground.enableBackgroundExecution();
  }

  // 请求所需权限
  Future<void> _requestPermissions() async {
    await Permission.notification.request(); // 请求通知权限
    await Permission.systemAlertWindow.request(); // 请求悬浮窗权限
    await Permission.backgroundRefresh.request(); // 请求后台刷新权限
  }

  void keepWebSocketConnection() {
    Timer.periodic(const Duration(seconds: 10), (timer) {
      channel?.sink.add('ping'); // 发送 ping 以保持连接
    });
  }

  // 处理接收到的消息
  void _handleMessage(String data) {
    Map<String, dynamic> jsonData = json.decode(data);
    if (jsonData['code'] == 200) {
      DatabaseHelper().insertMessage({
        'cmd': jsonData['cmd'],
        'message': jsonData['message'],
        'data': jsonData['data'],
        'created_at': DateTime.now().toIso8601String(),
        'raw_json': data
      });
      _showNotification(jsonData['message'], jsonData['data']);
    }
  }

  // 显示通知
  Future<void> _showNotification(String title, String body) async {
    FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

    const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings = InitializationSettings(android: initializationSettingsAndroid);

    await flutterLocalNotificationsPlugin.initialize(initializationSettings);

    await flutterLocalNotificationsPlugin.show(
      0,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'xarr_notify_channel',
          'xarr通知',
          channelDescription: 'xarr通知',
          importance: Importance.high,
          priority: Priority.high,
          icon: 'ic_launcher', // 使用的不带后缀的资源名称
        ),
      ),
    );
  }

  // 删除 7 天前的消息
  void _deleteOldMessages() async {
    DateTime sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7));
    await DatabaseHelper().deleteMessagesOlderThan(sevenDaysAgo);
    _loadPreferences(); // 重新加载偏好以更新 UI
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('配置'),
        backgroundColor: Colors.blueAccent, // 主色调为蓝色
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0), // 增加整体间距
        child: SingleChildScrollView( // 允许页面滚动
          child: Column(
            children: [
              Card(
                elevation: 4, // 增加阴影效果
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10), // 圆角
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0), // 内部间距
                  child: Column(
                    children: [
                      TextField(
                        controller: _domainController,
                        decoration: const InputDecoration(labelText: '链接域名'),
                        style: TextStyle(fontSize: 18), // 增大字体
                      ),
                      const SizedBox(height: 8), // 增加输入框之间的间距
                      TextField(
                        controller: _uidController,
                        decoration: const InputDecoration(labelText: '用户UID'),
                        style: TextStyle(fontSize: 18), // 增大字体
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _keyController,
                        decoration: const InputDecoration(labelText: '连接密钥'),
                        style: TextStyle(fontSize: 18), // 增大字体
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16), // 按钮与输入框之间的间距

              // 使用 Card 包裹 SwitchListTile
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                child: SwitchListTile(
                  title: const Text('使用WSS'),
                  value: _isWSS,
                  activeColor: Colors.blueAccent,  // 更改开关活动时颜色
                  onChanged: (value) {
                    setState(() {
                      _isWSS = value;
                    });
                  },
                ),
              ),
              const SizedBox(height: 16),

              // 使用 Row 包裹连接按钮和查看消息列表按钮
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  SizedBox(
                    width: 140, // 统一按钮的宽度
                    child: ElevatedButton(
                      onPressed: _isConnected ? null : _connect, // 根据连接状态控制按钮可用性
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent, // 按钮颜色
                        padding: const EdgeInsets.symmetric(vertical: 16), // 按钮内边距
                        foregroundColor: Colors.black, // 按钮字体颜色
                      ),
                      child: const Text('连接'),
                    ),
                  ),
                  SizedBox(
                    width: 140, // 统一按钮的宽度
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => MessageListPage(messageNotifier: NotificationController.messageNotifier),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        padding: const EdgeInsets.symmetric(vertical: 16), // 按钮内边距
                        foregroundColor: Colors.black, // 按钮字体颜色
                      ),
                      child: const Text('查看消息列表'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                _connectionStatus,
                style: TextStyle(
                  fontSize: 18, // 字体大小
                  fontWeight: FontWeight.bold, // 加粗
                  color: _connectionStatus == '已连接' ? Colors.green : Colors.red, // 状态颜色
                ),
              ),
              const SizedBox(height: 16),

              // 增加删除 7 天前消息的按钮
              ElevatedButton(
                onPressed: _deleteOldMessages,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueGrey, // 设置按钮颜色
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  foregroundColor: Colors.redAccent, // 设置按钮字体颜色
                ),
                child: const Text('删除 7 天前的消息'),
              ),
            ],
          ),
        ),
      ),
    );
  }

}

class NotificationController {
  static ValueNotifier<List<Map<String, dynamic>>> messageNotifier = ValueNotifier([]);

  static void sendMessageNotification(Map<String, dynamic> jsonData) {
    messageNotifier.value.add({
      'cmd': jsonData['cmd'],
      'message': jsonData['message'],
      'data': jsonData['data'],
      'created_at': DateTime.now().toIso8601String(),
      'raw_json': json.encode(jsonData),
    });
  }
}

class MessageListPage extends StatefulWidget {
  final ValueNotifier<List<Map<String, dynamic>>> messageNotifier;

  MessageListPage({required this.messageNotifier});

  @override
  _MessageListPageState createState() => _MessageListPageState();
}

class _MessageListPageState extends State<MessageListPage> {
  @override
  void initState() {
    super.initState();
    _loadMessages();

    widget.messageNotifier.addListener(() {
      setState(() {});
    });
  }

  void _loadMessages() async {
    List<Map<String, dynamic>> messages = await DatabaseHelper().getMessages();
    // 将消息列表反转
    widget.messageNotifier.value = messages.reversed.toList(); // 倒序显示
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('消息列表'),
        backgroundColor: Colors.blueAccent, // 修改主色调为蓝色
      ),
      body: ValueListenableBuilder<List<Map<String, dynamic>>>(
        valueListenable: widget.messageNotifier,
        builder: (context, messages, child) {
          return ListView.builder(
            itemCount: messages.length,
            itemBuilder: (context, index) {
              return Card( // 每个消息项使用 Card 包裹
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10), // 增加圆角
                ),
                child: ListTile(
                  title: Column( // 使用 Column 使时间与内容换行显示
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${messages[index]['created_at']}',
                        style: const TextStyle(fontSize: 16, color: Colors.black54), // 时间字体大小与颜色
                      ),
                      Text(
                        '${messages[index]['message']}',
                        style: const TextStyle(fontSize: 18, color: Colors.blueAccent), // 内容字体大小与颜色
                      ),
                    ],
                  ),
                  subtitle: Text(
                    '${messages[index]['data']}',
                    style: const TextStyle(color: Colors.black54), // 设置副标题的颜色
                  ),
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (context) {
                        Map<String, dynamic> jsonData = json.decode(messages[index]['raw_json']); // 解码为 Map
                        String formattedJson = const JsonEncoder.withIndent('  ').convert(jsonData); // 格式化 JSON 数据

                        return AlertDialog(
                          title: const Text('原始数据', style: TextStyle(color: Colors.blue)), // 将标题颜色设为蓝色
                          content: SingleChildScrollView( // 添加滚动可以避免数据过大
                            child: Text(
                              formattedJson,
                              style: const TextStyle(color: Colors.black), // 内容颜色保持黑色
                            ),
                          ),
                          actions: [
                            TextButton(
                              child: const Text('关闭', style: TextStyle(color: Colors.blue)), // 将关闭按钮颜色设为蓝色
                              onPressed: () {
                                Navigator.of(context).pop();
                              },
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
