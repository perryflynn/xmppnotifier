#!/usr/bin/perl

# XMPP Notifier for new Emails
# by Christian Blechert
# https://github.com/perryflynn/xmppnotifier/

use strict;
use warnings;

use Mail::IMAPClient;
use Mail::IMAPClient::BodyStructure;
use DateTime;
use Date::Parse;
use Encode;
use Net::XMPP;
use XML::Simple;


#-> Load Config
my $configfile = "xmppnotify.xml";
my $parser = new XML::Simple;
my $tree = $parser->XMLin($configfile, KeepRoot => 1);


sub openxmpp 
{
   #-> Connect XMPP
   my ($cxmpp) = @_;
   my $xmpp = new Net::XMPP::Client();
   my $status = $xmpp->Connect(
      hostname => $cxmpp->{server}, 
      componentname => $cxmpp->{componentname}, 
      port => $cxmpp->{port}, 
      connectiontype => 'tcpip', 
      tls => $cxmpp->{tls}
   );

   die "XMPP Connection failed: $!" unless defined $status;

   #-> Login XMPP
   my($res, $msg) = $xmpp->AuthSend(
      username => $cxmpp->{username}, 
      password => $cxmpp->{password}, 
      resource => $cxmpp->{resource}
   );

   die "XMPP Auth failed ", defined $msg ? $msg : '-', " $!" unless defined $res and $res eq 'ok';
   
   return $xmpp;
}


sub openimap
{
   my ($cimap) = @_;
   my $imap = Mail::IMAPClient->new(
      Server => $cimap->{server}, 
      User => $cimap->{username}, 
      Password => $cimap->{password}, 
      Port => $cimap->{port}, 
      Ssl => $cimap->{ssl}, 
      Uid => 1
   );
   return $imap;
}


sub isblacklisted
{
   my ($name, $blacklist) = @_;
   if(ref $blacklist ne 'ARRAY')
   {
      $blacklist = [$blacklist];
   }
   foreach my $blackitem (@{ $blacklist })
   {
      if($blackitem)
      {
         my $re = qr/$blackitem/;
         if($name =~ $re)
         {
            return 1;
         }
      }
   }
   return 0;
}


#-> Date foo
my $lastcheck = DateTime->from_epoch(epoch => str2time($tree->{xmlnotify}->{lastcheck}));
my $datestr = $lastcheck->strftime("%{day}-%{month_abbr}-%Y");


#--> List all folders
if($ARGV[0] eq "--folders")
{
   print "List all IMAP folders:\n";
   my $cimaps = $tree->{xmlnotify}->{imapaccounts}->{imapaccount};
   if(ref $cimaps ne 'ARRAY')
   {
      $cimaps = [$cimaps];
   }
   foreach my $cimap (@{ $cimaps })
   {
      print "\n- ".$cimap->{alias}."\n\n";
      my $imap = openimap($cimap);
      
      foreach my $folder ($imap->folders)
      {
         print "   ".$folder." ";
         if(isblacklisted($folder, $cimap->{folderblacklist}->{folder}))
         {
            print "[blacklisted]";
         }
         print "\n";
      }
      
      $imap->close();
   }
   print "\nDone!\n";
}


#--> XMPP notify!
elsif($ARGV[0] eq "--notify")
{

   #--> Open XMPP
   my $xmpp = openxmpp($tree->{xmlnotify}->{xmpp});
   my $xmpprecipient = $tree->{xmlnotify}->{xmpp}->{recipient};

   my $cimaps = $tree->{xmlnotify}->{imapaccounts}->{imapaccount};
   if(ref $cimaps ne 'ARRAY')
   {
      $cimaps = [$cimaps];
   }
   foreach my $cimap (@{ $cimaps })
   {
      print "- ".$cimap->{alias}."\n";
      my $imap = openimap($cimap);
      
      foreach my $folder ($imap->folders)
      {
         print $folder." ";
         if(!isblacklisted($folder, $cimap->{folderblacklist}->{folder}))
         {
            if($imap->select($folder))
            {
               my @msgIDs = $imap->search("NOT BEFORE ".$datestr);
               my $i=0;
               if($#msgIDs ge 0)
               {
                  foreach my $msgID (@msgIDs)
                  {
                     my $envelope = $imap->get_envelope($msgID);
                     my $esubject = Encode::decode('MIME-Header', $envelope->{subject});
                     my $edate = $envelope->{date};
                     my $ename = $envelope->sender->[0]->{mailboxname}."@".$envelope->sender->[0]->{hostname};
                     if($envelope->{sender}->[0]->{personalname} ne 'NIL')
                     {
                        $ename = $envelope->{sender}->[0]->{personalname};
                     }

                     my $date = DateTime->from_epoch(epoch => str2time($edate));
                     
                     if(DateTime->compare($date, $lastcheck)>=0)
                     {
                        my $message = "[".$cimap->{alias}."] In ".$folder.": ".$esubject." (".$ename.")";
                        $xmpp->MessageSend(to => $xmpprecipient, body => $message);
                        $i++;
                     }
                  }
                  
               }
               print "(".$i.")\n";
            }
            else
            {
               print "(failed to select)\n";
            }
         }
         else
         {
            print "(blacklisted)\n";
         }
      }
      
      $imap->close();
   }

   $xmpp->Disconnect();

   #--> Store Date
   $tree->{xmlnotify}->{lastcheck} = DateTime->now()->strftime("%a, %d %b %Y %H:%M:%S %z");
   XMLout($tree, KeepRoot => 1, NoAttr => 1, OutputFile => $configfile);

}
else
{
   print "Options: --folders, --notify\n";
}
