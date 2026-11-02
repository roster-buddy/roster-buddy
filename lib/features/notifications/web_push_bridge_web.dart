import 'dart:convert';
import 'dart:js_interop';

@JS('rosterPushStatus') external JSPromise<JSString> _status(JSString user);
@JS('rosterPushEnable') external JSPromise<JSString> _enable(JSString token,JSString user);
@JS('rosterPushDisable') external JSPromise<JSString> _disable(JSString token,JSString user);
@JS('rosterPushTest') external JSPromise<JSString> _test(JSString token);

class WebPushBridge {
 static Future<Map<String,dynamic>> _read(JSPromise<JSString> value) async {
   final data=jsonDecode((await value.toDart).toDart) as Map<String,dynamic>;
   if(data['error']!=null) throw StateError(data['error'] as String);
   return data;
 }
 static Future<Map<String,dynamic>> status(String user)=>_read(_status(user.toJS));
 static Future<Map<String,dynamic>> enable(String token,String user)=>_read(_enable(token.toJS,user.toJS));
 static Future<Map<String,dynamic>> disable(String token,String user)=>_read(_disable(token.toJS,user.toJS));
 static Future<Map<String,dynamic>> test(String token)=>_read(_test(token.toJS));
}
