Informs you on XMPP/Jabber when new E-Mails arrive.

Features
-

- Perl based
- XML Configuration
- Regex based folder blacklist

Requirements
-

- Mail::IMAPClient
- DateTime
- Date::Parse
- Net::XMPP
- XML::Simple

Usage
-
```
./xmppnotify.pl --folders # List all available folders
./xmppnotify.pl --notify # Check and send XMPP messages
```

Cronjob
- 
```
*/10 * * * * cd /home/perryflynn/xmppnotify; ./xmppnotify.pl --notify > xmppnotify.log
```
