import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'web_push_bridge.dart';

class PushNotificationSettings extends StatefulWidget {
 const PushNotificationSettings({super.key});
 @override State<PushNotificationSettings> createState()=>_PushNotificationSettingsState();
}
class _PushNotificationSettingsState extends State<PushNotificationSettings> {
 String _state='loading',_message='Checking notification support…';
 bool _busy=false;
 @override void initState(){super.initState();if(kIsWeb) _load();}
 Future<void> _load() async {
   try {
     final user=Supabase.instance.client.auth.currentUser?.id ?? '';
     final value=await WebPushBridge.status(user);
     if(mounted) setState((){_state=value['state'] as String;_message=value['message'] as String;});
   } catch (_) {
     if(mounted) setState((){_state='available';_message='Refresh Roster Buddy to load notification support.';});
   }
 }
 Future<void> _run(String action) async {
   if(_busy) return;
   setState(()=>_busy=true);
   try {
     final session=Supabase.instance.client.auth.currentSession;
     if(session==null) throw StateError('Please sign in again.');
     final value=await switch(action){
       'enable'=>WebPushBridge.enable(session.accessToken,session.user.id),
       'test'=>WebPushBridge.test(session.accessToken),
       _=>WebPushBridge.disable(session.accessToken,session.user.id),
     };
     if(mounted) setState((){_state=value['state'] as String;_message=value['message'] as String;});
   } catch(error) {
     if(mounted) setState(()=>_message=error.toString().replaceFirst('Bad state: ',''));
   } finally {if(mounted) setState(()=>_busy=false);}
 }
 @override Widget build(BuildContext context){
   if(!kIsWeb) return const SizedBox.shrink();
   return Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(
     crossAxisAlignment:CrossAxisAlignment.stretch,children:[
       const Text('Device notifications',style:TextStyle(fontWeight:FontWeight.w800,fontSize:18)),
       const SizedBox(height:8),Text(_message),
       if(_state=='install') const Text('In Safari: Share → Add to Home Screen. Then open the Roster Buddy icon and return to this page.'),
       if(_state=='available') FilledButton.icon(
         onPressed:_busy?null:()=>_run('enable'),icon:const Icon(Icons.notifications_active_outlined),label:const Text('Enable notifications')),
       if(_state=='enabled') ...[
         FilledButton.icon(onPressed:_busy?null:()=>_run('test'),icon:const Icon(Icons.notifications_outlined),label:const Text('Send test notification')),
         TextButton(onPressed:_busy?null:()=>_run('disable'),child:const Text('Turn off on this device')),
       ],
       if(_busy) const LinearProgressIndicator(),
       TextButton(onPressed:_busy?null:_load,child:const Text('Refresh notification status')),
     ],
   )));
 }
}
