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
          title: 'xarr_notify',
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
        channel?.stream.listen((data) {
          _handleMessage(data);
        }, onError: (error) {
          setState(() {
            _connectionStatus = '连接失败';
          });
          print('Error: $error');
        }, onDone: () {
          setState(() {
            _connectionStatus = '未连接';
          });
        });
    
        setState(() {
          _connectionStatus = '已连接';
        });
    
        startBackgroundService(); // 启动后台服务
      }
    
      // 启动后台服务
      Future<void> startBackgroundService() async {
        await _requestPermissions(); // 请求权限
    
        var androidConfig = const FlutterBackgroundAndroidConfig(
          notificationTitle: "后台服务",
          notificationText: "该服务在后台运行。",
            notificationImportance : AndroidNotificationImportance. normal,
            notificationIcon : AndroidResource(name: 'ic_launcher', defType: 'mipmap'),
            enableWifiLock : true,
            showBadge : true,    shouldRequestBatteryOptimizationsOff :true
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
    
      @override
      Widget build(BuildContext context) {
        return Scaffold(
          appBar: AppBar(title: const Text('配置')),
          body: Column(
            children: [
              TextField(controller: _domainController, decoration: const InputDecoration(labelText: '链接域名')),
              TextField(controller: _uidController, decoration: const InputDecoration(labelText: '用户UID')),
              TextField(controller: _keyController, decoration: const InputDecoration(labelText: '连接密钥')),
              SwitchListTile(
                title: const Text('使用WSS'),
                value: _isWSS,
                onChanged: (value) {
                  setState(() {
                    _isWSS = value;
                  });
                },
              ),
              ElevatedButton(
                onPressed: _connect,
                child: const Text('连接'),
              ),
              Text(_connectionStatus),
              ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => MessageListPage(messageNotifier: NotificationController.messageNotifier),
                    ),
                  );
                },
                child: const Text('查看消息列表'),
              ),
            ],
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
        widget.messageNotifier.value = messages;
      }
    
      @override
      Widget build(BuildContext context) {
        return Scaffold(
          appBar: AppBar(title: const Text('消息列表')),
          body: ValueListenableBuilder<List<Map<String, dynamic>>>(
            valueListenable: widget.messageNotifier,
            builder: (context, messages, child) {
              return ListView.builder(
                itemCount: messages.length,
                itemBuilder: (context, index) {
                  return ListTile(
                    title: Text('${messages[index]['created_at']} ${messages[index]['message']}'),
                    subtitle: Text('${messages[index]['data']}'),
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (context) {
                          return AlertDialog(
                            title: const Text('原始数据'),
                            content: Text(messages[index]['raw_json']),
                            actions: [
                              TextButton(
                                child: const Text('关闭'),
                                onPressed: () {
                                  Navigator.of(context).pop();
                                },
                              ),
                            ],
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          ),
        );
      }
    }