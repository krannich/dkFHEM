##############################################
## Stand: 02.04.2017
##############################################
# $Id$
package main;

use strict;
use warnings;
use POSIX;
use Time::Local;

sub dkUtils_Initialize($$) {
 	my ($hash) = @_;
}


#######################################
##
##
## ALLGEMEINE FUNKTIONEN
##
##
#######################################

sub dkIsHomematic($) {
	my ($device) = @_;	
	my $device_type = dkGetAttr($device, "model");
	if (substr($device_type, 0, 2) eq "HM") {
		return 1;
	} else {
		return 0;
	}
}

sub dkIsAction($) {
	my ($device) = @_;
	if (substr($device, 0, 7) eq "Action_") {
		return 1;
	} else {
		return 0;
	}
}

sub dkIsOn($) {
	my ($input) = @_;	
	my @devices = split(',', $input);
	my @active_devices;
	
	foreach my $device (@devices) {
		if (dkExists($device)) {
			my $state = dkGetState($device);
			if ($state eq "on") {
				push(@active_devices, dkGetAlias($device));
			}
		}
	}
	return join(", ", sort(@active_devices) );
}

sub dkSetDevice($$) {
	my ($input, $value) = @_;	
	my @devices = split(',', $input);
	my @validated_devices;

	foreach my $device (@devices) {
		if (dkExists($device)) {
			if (dkIsHomematic($device)) {
				my $state = dkGetState($device);
				if ($state ne $value && $state ne "unknown") {
					push(@validated_devices, $device);
				}
			} else {
				push(@validated_devices, $device);
			}
		}
	}

	my $cleaned_device_list = join(",", @validated_devices);
	if ($cleaned_device_list ne "") {
		fhem("set $cleaned_device_list $value", 1);
	}
		
}



sub dkOn($) {
	my($device) = @_;
	dkSetDevice($device, "on");
}


sub dkOff($) {
	my($device) = @_;
	dkSetDevice($device, "off");
}


sub dkToggle($) {
	my ($device) = @_;
	fhem("set $device toggle", 1);
}



sub dkOnFor($$) {
	my ($device, $durationInHours) = @_;
	if (dkGetState($device) eq "on") { return 0; }
	
	dkOn($device);
	dkAutoOff($device, "on", $durationInHours);
}


sub dkAutoOff($$$) {
	my ($device, $event, $durationInHours) = @_;
	my ($deviceAutoOff) = $device . "_AutoOff";	
	if (dkExists($deviceAutoOff)) { fhem ("delete $deviceAutoOff"); }
	if ($event eq "on") {
		my $mytime = dkTimeAddHoursHMS($durationInHours);
		fhem ("define $deviceAutoOff at $mytime { dkOff('$device') }", 1);
	}
}


sub dkSetBlinds($$) {
	my ($input, $value) = @_;	
	my @devices = split(',', $input);
	my @validated_devices;

	if ($value eq "auf") { $value = "on"; }
	if ($value eq "zu") { $value = "off"; }

	foreach my $device (@devices) {
		if (dkExists($device)) {
			my $state = dkGetState($device);
			if ($state ne $value) {
				push(@validated_devices, $device);
			}
		}
	}

	my $cleaned_device_list = join(",", @validated_devices);
	if ($cleaned_device_list ne "") {
		fhem("set $cleaned_device_list $value", 1);
	}
	
}


#######################################
##
##
## Device States, Alias und Parameter
##
##
#######################################

sub dkGetReading($$){
	my($device, $reading) = @_;
	return ReadingsVal($device, $reading, "unknown");
}


sub dkGetState($){
	my($device) = @_;
	return ReadingsVal($device, "state", "unknown");
}


sub dkGetStateLastChange($) {
	my($device) = @_;	
	return ReadingsTimestamp($device,"state","0");
}


sub dkGetAttr($$) {
	my($device, $attr) = @_;	
	return AttrVal($device, $attr, "unknown");
}


sub dkGetAlias($) {
	my($device) = @_;	
	return AttrVal($device, "alias", "unknown");
}


sub dkSetValue($$) {
	my($device, $value) = @_;
	fhem("set $device $value", 1);
}


sub dkSetReading($$$) {
	my($device, $reading, $value) = @_;
	fhem("setreading $device $reading $value", 1);
}

#######################################

sub dkIsXmas() {
	my $is_xmas = dkGetState("setting_xmas");
	if ($is_xmas eq "on") { return 1; } else { return 0; }
}


sub dkIsDND() {
	my $is_xmas = dkGetState("setting_dnd");
	if ($is_xmas eq "on") { return 1; } else { return 0; }
}

sub dkIsParentsHome() {
	my $is_parents_home = dkGetState("rgr_Parents");
	if ($is_parents_home eq "home") { return 1; } else { return 0; }
}


#######################################

sub dkExists($) {
	my ($object) = @_;
	if ( Value($object) ) {	return 1; } else { return 0; }
}


sub dkValueExists($) {
	my ($object) = @_;
	if ( Value($object) eq "???" || ReadingsVal($object, "state", "???") eq "???" ) {
		return 0;
	} else {
		return 1;
	}
}


#######################################
##
##
## Watchdog
##
##
#######################################

sub dkWatchdog($$$) {
	my ($device, $state, $durationInHours) = @_;
	my $device_state = dkGetState($device);
	my $device_alias = dkGetAlias($device);
	
	dkRemoveWatchdog($device);
	if ($device_state eq $state) {
		dkAddWatchdog($device,$state,$durationInHours);
		dkPush("device", "$device_alias ist noch angeschaltet.");
	} 
}


sub dkAddWatchdog($$$) {
	my($device, $state, $durationInHours) = @_;
	my $device_notify = $device . "_dkWatchdog";
	my $mytime = dkTimeAddHoursHMS($durationInHours);
	fhem("define $device_notify at $mytime { dkWatchdog('$device', '$state', $durationInHours) }", 1);
}


sub dkRemoveWatchdog($) {
	my($device) = @_;
	my $device_notify = $device . "_dkWatchdog";
	if (dkExists($device_notify)) {
		fhem ("delete $device_notify", 1);
	}
}


#######################################
##
##
## Zeit-Funktionen
##
##
#######################################

sub dkCurrentHour($$) {
	my ($operator,$hour) = @_;
	my $currenthour = strftime("%H", localtime)+0; # +0 = hack to format as integer
	my $command = "$currenthour $operator $hour";
	if (eval($command)) {
		return 1;
	} else {
		return 0;
	}
}


sub dkTimeFormat($){
	my $Sekundenzahl = @_;
	return sprintf("%02d:%02d:%02d", ($Sekundenzahl/60/60)%24, ($Sekundenzahl/60)%60, ($Sekundenzahl)%60 );
}


sub dkTimeAgeInHours($$) {
	my ($now, $timestamp) = @_;
	my @splitdatetime = split(/ /,$timestamp);
	my @splitdate = split(/-/, $splitdatetime[0]);
	my @splittime = split(/:/, $splitdatetime[1]);
	my $last_state_time =  timelocal($splittime[2], $splittime[1], $splittime[0], $splitdate[2], $splitdate[1]-1, $splitdate[0]);
	my $age_in_hours = ($now - $last_state_time) / 3600;		
	return $age_in_hours;
}

sub dkTimeHoursToHMS($) {
	my ($hours) = @_;
	$hours = $hours * 60 * 60;
	return strftime("\%H:\%M:\%S", gmtime($hours) );
}

sub dkTimeAddHoursHMS($) {
	my ($hours) = @_;
	$hours = $hours * 60 * 60;
	return strftime("\%H:\%M:\%S", localtime(time + $hours) );
}

#######################################
##
##
## Text-Converter
##
##
#######################################

sub dkGoogleMapsDuration($) {
	my ($value) = @_; 

	my $minutes = "0";
	my $hours = "0"; 

	if($value =~ /([\d]+) Minuten?/) { $minutes = $1; }
	if($value =~ /([\d]+) Stunden?/) { $hours = $1; }
	
	return sprintf("%02d:%02d",$hours,$minutes);
}



#######################################
##
##
## Sprachausgabe
##
##
#######################################

sub dkTalk($) {
	my ($message) = @_;
	if (!$message) { return; }
	$message =~ s/_/ /g;
	$message =~ s/-/ /g;
	fhem("set mytts tts $message", 1);
}


sub dkTalkAlarm() {
	dkTalk("Aufgepasst Ihr Wixer. Verpisst euch aus unserem Haus. Der Sicherheitsdienst ist informiert und tritt euch Fotzen gleich mächtig in den Arsch!");
}


#######################################
##
##
## Push Mitteilungen
##
##
#######################################

sub dkGlance($) {
	my ($message) = @_;
	if (!$message) { return; }
	fhem("set pushover glance title='FHEM' text='$message' device='dkPhone6s-DK'", 1);
}

sub dkPushDennis($) {
	my ($message) = @_;
	if (!$message) { return; }
	fhem("set pushover msg title='FHEM' message='$message' device='dkPhone6s-DK'", 1);
}

sub dkPush($$) {
	my ($type, $message) = @_;
	if (!$message || !$type) { return; }
		
	if ($type eq "default") 	  { fhem("set pushover msg title='FHEM' message='$message'", 1); }
	if ($type eq "warning") 	  { fhem("set pushover msg title='FHEM Warning' message='$message' sound='gamelan'", 1); }
	if ($type eq "alarm") 	  { fhem("set pushover msg title='FHEM Alarm' message='$message' priority=2 sound='siren' retry=30 expire=3600 ", 1); }
	if ($type eq "call") 	  { fhem("set pushover msg title='FHEM' message='$message' sound='bike'", 1); }
	if ($type eq "device") 	  { fhem("set pushover msg title='FHEM' message='$message' sound='bike'", 1); }
	if ($type eq "attention") { 	fhem("set pushover msg title='FHEM' message='$message' sound='bugle'", 1); }
	if ($type eq "magic") 	  { fhem("set pushover msg title='FHEM' message='$message' sound='magic'", 1); }
	if ($type eq "doorbell")  { fhem("set pushover msg title='FHEM' message='$message' sound='incoming'", 1); }

}

#######################################
##
##
## Textausgabe auf Fernseher
##
##
#######################################

sub dkDisplayText($) {
	my ($message) = @_;
	if (!$message) { return; }
	if ( dkGetState("SatReceiver") ne "on" ) { return; }
	fhem("set SatReceiver msg info 10 $message", 1);
}


#######################################
##
##
## DISHWASHER
##
##
#######################################

sub dkHandleDishwasher($) {
	my ($event) = @_;
	
	if ($event eq "on") {
		fhem("set data_dishwasher_status on", 1);
		fhem("setstate watchdog_dishwasher_autooff defined", 1);
		dkPush("default", "Der Geschirrspüler wurde angeschaltet.");		
	}
	
	if ($event eq "standby") {
		fhem("set data_dishwasher_status standby", 1);
	}
	
	if ($event eq "off") {
		my $aktueller_betrieb_in_euro = ( ReadingsVal("EG_Kueche_Sensor_Steckdose_Pwr","energy","0") - ReadingsVal("data_dishwasher_status","energy","0") ) / 1000 * ReadingsVal("data_euro_pro_kwh","state","");
		$aktueller_betrieb_in_euro = int(100 * $aktueller_betrieb_in_euro + 0.5) / 100;
		fhem("setreading data_dishwasher_status Kosten $aktueller_betrieb_in_euro", 1);
		
		fhem("set data_dishwasher_status,EG_Kueche_Sensor_Steckdose_Sw off", 1);
		
		dkPush("default", "Der Geschirrspüler ist fertig. Kosten: $aktueller_betrieb_in_euro €.");
		dkTalk("Der Geschirrspüler ist fertig!");
	}
	
}


#######################################
##
##
## FHEM ROUTINES
##
##
#######################################

sub dkFHEM($) {
	my ($event) = @_;
	
	if ($event eq "INITIALIZED") {
		dkSetDefaults();
		fhem("set SCC led 00", 1);
		dkTalk("System gestartet.");
		my ($anlagenstatus) = dkGetState("data_anlagenstatus");
		dkPushDennis("System gestartet. Alarmanlage: $anlagenstatus");
	}
	
	if ($event eq "SHUTDOWN") {
		dkTalk("System fährt runter.");
	}
	
}


sub dkSetDefaultValue($$) {
	my ($object,$value) = @_;
	if ( !dkValueExists($object) ) { fhem("set $object $value", 1); }	
}

sub dkSetDefaults() {
	
	dkSetDefaultValue("data_anlagenstatus", "unscharf");
	dkSetDefaultValue("data_cominghome", "none");
	dkSetDefaultValue("data_leavinghome", "none");
	dkSetDefaultValue("data_avrvolume", 0);

}





#######################################
##
##
## HELPERS
##
##
#######################################

sub _isWeekend() {
	my ($sec,$min,$hour,$mday,$month,$year,$wday,$yday,$isdst) = localtime;
	# Samstag = 0, Sonntag = 6
	if($wday == 0 || $wday == 6) {
		return 1;
	} else {
		return 0;
	}
}



sub eq3StateFormat() {
  my $name = "eq3";

  my $ret ="";
  my $lastCheck = ReadingsTimestamp($name,"MATCHED_READINGS","???");
  $ret .= '<div style="text-align:left">';   
  $ret .= 'last <a title="eq3-downloads" href="http://www.eq-3.de/downloads.html">homematic</a>-fw-check => '.$lastCheck;    
  $ret .= '<br><br>';    
  $ret .= '<pre>';   
  $ret .= "| device                  | model                   | old_fw | new_fw | release    |\n";  
  $ret .= "------------------------------------------------------------------------------------\n";  
  my $check = ReadingsVal($name,"newFwForDevices","???");    
  if($check eq "no fw-updates needed!") {        
    $ret .= '| '.$check.'                                                            |';     
  } else {         
    my @devices = split(',',$check);         
    foreach my $devStr (@devices) {
      my ($dev,$md,$ofw,$idx,$nfw,$date) = $devStr =~ m/^([^\s]+)\s\(([^\s]+)\s\|\sfw_(\d+\.\d+)\s=>\sfw(\d\d)_([\d\.]+)\s\|\s([^\)]+)\)$/;          
      my $link = ReadingsVal($name,"fw_link-".$idx,"???");           
      $ret .= '| ';          
      $ret .= '<a href="/fhem?detail='.$dev.'">';            
      $ret .= sprintf("%-23s",$dev);             
      $ret .= '</a>';            
      $ret .= " | ";             
      $ret .= '<b'.(($md eq "?")?' title="missing attribute model => set device in teach mode to receive missing data" style="color:yellow"':' style="color:lightgray"').'>';            
      $ret .= sprintf("%-23s",$md);          
      $ret .= '</b>';            
      $ret .= " | ";             
      $ret .= '<b'.(($ofw eq "0.0")?' title="missing attribute firmware => set device in teach mode to receive missing data" style="color:yellow"':' style="color:lightgray"').'>';              
      $ret .= sprintf("%6s",$ofw);           
      $ret .= '</b>';            
      $ret .= " | ";             
      $ret .= '<a title="eq3-firmware.tgz" href="'.$link.'">';           
      $ret .= '<b style="color:red">';           
      $ret .= sprintf("%6s",$nfw);           
      $ret .= '</b>';            
      $ret .= '</a>';            
      $ret .= " | ";             
      $ret .= sprintf("%-10s",$date);            
      $ret .= " |\n";        
    }   
  }  
  $ret .= '</pre>';  
  $ret .= '</div>';  
  return $ret;
}



#######################################

1;

=pod
=begin html

  	<a name="dkUtils"></a><h3>dkUtils</h3>
	<ul>
		dkUtils<br>
		<br>
		<a name="dkUtils_define"></a><b>Define</b>
		<ul>
			<code><b>Funktionen</B></code>
		</ul>
	</ul>

=end html

=cut
