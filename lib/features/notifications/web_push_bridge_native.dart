class WebPushBridge {
 static Future<Map<String,dynamic>> status(String user) async => {'state':'unsupported','message':'Web Push is available in the browser/Home Screen version.'};
 static Future<Map<String,dynamic>> enable(String token,String user) => status(user);
 static Future<Map<String,dynamic>> disable(String token,String user) async => {'state':'available'};
 static Future<Map<String,dynamic>> test(String token) => status('');
}
