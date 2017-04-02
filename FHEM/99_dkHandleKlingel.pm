##############################################
## Stand: 29.01.2017
##############################################
# $Id$
package main;

use strict;
use warnings;
use POSIX;
use Time::Local;

sub dkHandleKlingel_Initialize($$) {
 	my ($hash) = @_;
}

#######################################
##
##
## FUNKTIONEN
##
##
#######################################

sub dkRouteKlingel($$) {
	my ($device, $event) = @_;
	my $action = "dkAct_" . $device;
	my @events = split / /, $event;
	
	my $button = $events[0];
	$device = $device . "_";
	$button =~ s/$device//g;
	my $button_event = $events[1];

	my $coderef=__PACKAGE__->can($action);
	if ($coderef) { 
		$coderef->($button, $button_event);
	}
}


#######################################
## ACTIONS
#######################################

sub dkAct_Klingel_01($$) {
	my ($button,$button_event) = @_;	
	if ($button eq "CH_04") {
		fhem("set mytts tts :dingdong1.mp3:", 1);
		dkDisplayText('Ding dong! Seitentür.');
		if (!dkIsParentsHome()) {
			dkPush("incoming", "Ding dong! Seitentür.");
		}
		#fhem("set fritzbox_control ring 610,611 10 News", 1);
	}
}


sub dkAct_Klingel_02($$) {
	my ($button,$button_event) = @_;	
	if ($button eq "CH_04") {
		fhem("set mytts tts :dingdong2.mp3:", 1);
		dkDisplayText('Ding dong! Haustür.');
		if (!dkIsParentsHome()) {
			dkPush("incoming", "Ding dong! Haustür.");
		}
		#fhem("set fritzbox_control ring 610,611 10 News", 1);
	}
}


#######################################
##
##
## INTERNE FUNKTIONEN
##
##
#######################################


1;