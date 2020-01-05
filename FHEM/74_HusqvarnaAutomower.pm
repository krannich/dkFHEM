###############################################################################
# 
#  (c) 2018-2019 Copyright: Dr. Dennis Krannich (blogger at krannich dot de)
#  All rights reserved
#
#  This script is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#
# $Id: 74_HusqvarnaAutomower.pm 19200 2019-04-16 18:39:00Z krannich $
#  
################################################################################

package main;

my $missingModul = "";

use strict;
use warnings;
use Time::Local;
use JSON;
use HttpUtils;
use Blocking;

eval "use JSON;1" or $missingModul .= "JSON ";

my $version = "0.5.2";

use constant AUTHURL => "https://iam-api.dss.husqvarnagroup.net/api/v3/";
use constant APIURL => "https://amc-api.dss.husqvarnagroup.net/app/v1/";

##############################################################
#
# Declare functions
#
##############################################################

sub HusqvarnaAutomower_Initialize($);
sub HusqvarnaAutomower_Define($$);

sub HusqvarnaAutomower_Notify($$);

sub HusqvarnaAutomower_Attr(@);
sub HusqvarnaAutomower_Set($@);
sub HusqvarnaAutomower_Undef($$);

sub HusqvarnaAutomower_CONNECTED($@);
sub HusqvarnaAutomower_CMD($$);


##############################################################

sub HusqvarnaAutomower_Initialize($) {
	my ($hash) = @_;
	
    $hash->{SetFn}      = "HusqvarnaAutomower_Set";
    $hash->{DefFn}      = "HusqvarnaAutomower_Define";
    $hash->{UndefFn}    = "HusqvarnaAutomower_Undef";
    $hash->{NotifyFn} 	= "HusqvarnaAutomower_Notify";
    $hash->{AttrFn}     = "HusqvarnaAutomower_Attr";
    $hash->{AttrList}   = "username " .
                          "password " .
                          "mower " .
                          "language " .
                          "interval " .
                          $readingFnAttributes;

    foreach my $d(sort keys %{$modules{HusqvarnaAutomower}{defptr}}) {
        my $hash = $modules{HusqvarnaAutomower}{defptr}{$d};
        $hash->{HusqvarnaAutomower}{version} = $version;
    }

}


sub HusqvarnaAutomower_Define($$){
    my ( $hash, $def ) = @_;
    my @a = split( "[ \t]+", $def );
    my $name = $a[0];

    return "too few parameters: define <NAME> HusqvarnaAutomower" if( @a < 1 ) ;
    return "Cannot define HusqvarnaAutomower device. Perl modul $missingModul is missing." if ( $missingModul );

    %$hash = (%$hash,
        NOTIFYDEV => "global,$name",
        HusqvarnaAutomower => { 
            CONNECTED				=> 0,
            version     				=> $version,
            token					=> '',
            provider					=> '',
            user_id					=> '',
            mower_id					=> '',
            mower_name				=> '',
            mower_model 				=> '',
            mower_battery 			=> 0,
            mower_activity 		 	=> '',
            mower_state 		 		=> '',
			mower_mode				=> '',
            mower_cuttingMode		=> '',
            mower_commandStatus		=> '',
            mower_lastLatitude 		=> 0,
            mower_lastLongitude 		=> 0,
            mower_nextStart 			=> 0,
            mower_nextStartSource 	=> '',
            mower_restrictedReason	=> '',
            mower							=> 0,
            batteryPercent					=> 0,
            username 						=> '',
            language 						=> 'DE',
            password 						=> '',
            interval    					=> 300,
            expires 						=> time(),
			mower_geofence					=> '',
			mower_headlights				=> '',
			mower_searchChargingStation		=> '',
			mower_fota						=> '',
			mower_gpsNavigation				=> '',
			mower_weatherTimer				=> '',
			mower_corridorWidth				=> '',
			mower_connected					=> '',
			mower_lastErrorCode				=> '',
			mower_lastErrorCodeTimestamp	=> '',
			mower_errorConfirmable			=> '',
        },
    );
	
	$attr{$name}{room} = "HusqvarnaAutomower" if( !defined( $attr{$name}{room} ) );
	
	HusqvarnaAutomower_CONNECTED($hash,'initialized');

	return undef;

}


sub HusqvarnaAutomower_Notify($$) {
    
    my ($hash,$dev) = @_;
    my ($name) = ($hash->{NAME});
    
	if (AttrVal($name, "disable", 0)) {
		Log3 $name, 5, "Device '$name' is disabled, do nothing...";
		HusqvarnaAutomower_CONNECTED($hash,'disabled');
	    return undef;
    }

 	my $devname = $dev->{NAME};
    my $devtype = $dev->{TYPE};
    my $events = deviceEvents($dev,1);
	return if (!$events);
    
    $hash->{HusqvarnaAutomower}->{updateStartTime} = time();    
    
    if ( $devtype eq 'Global') {
	    if (
		    grep /^INITIALIZED$/,@{$events}
		    or grep /^REREADCFG$/,@{$events}
	        or grep /^DEFINED.$name$/,@{$events}
	        or grep /^MODIFIED.$name$/,@{$events}
	    ) {
	        HusqvarnaAutomower_APIAuth($hash);
	    }
	} 
	
	if ( $devtype eq 'HusqvarnaAutomower') {
		if ( grep(/^state:.authenticated$/, @{$events}) ) {
     	   	HusqvarnaAutomower_getMower($hash);
		}
		
		if ( grep(/^state:.connected$/, @{$events}) ) {
			HusqvarnaAutomower_DoUpdate($hash);
		}
			
		if ( grep(/^state:.disconnected$/, @{$events}) ) {
		    Log3 $name, 3, "Reconnecting...";
			HusqvarnaAutomower_APIAuth($hash);
		}
	}
            
    return undef;
}


sub HusqvarnaAutomower_Attr(@) {
	
    my ( $cmd, $name, $attrName, $attrVal ) = @_;
    my $hash = $defs{$name};
		
	if( $attrName eq "disable" ) {
        if( $cmd eq "set" and $attrVal eq "1" ) {
            RemoveInternalTimer($hash);
            readingsSingleUpdate ( $hash, "state", "disable", 1 );
            Log3 $name, 3, "$name - disabled";
        }

        elsif( $cmd eq "del" ) {
            readingsSingleUpdate ( $hash, "state", "active", 1 );
            Log3 $name, 3, "$name - enabled";
        }
    }
    
	elsif( $attrName eq "username" ) {
		if( $cmd eq "set" ) {
		    $hash->{HusqvarnaAutomower}->{username} = $attrVal;
		    Log3 $name, 3, "$name - username set to " . $hash->{HusqvarnaAutomower}->{username};
		}
	}

	elsif( $attrName eq "password" ) {
		if( $cmd eq "set" ) {
			$hash->{HusqvarnaAutomower}->{password} = $attrVal;
		    Log3 $name, 3, "$name - password set to " . $hash->{HusqvarnaAutomower}->{password};	
		}
	}

	elsif( $attrName eq "language" ) {
		if( $cmd eq "set" ) {
			$hash->{HusqvarnaAutomower}->{language} = $attrVal;
		    Log3 $name, 3, "$name - language set to " . $hash->{HusqvarnaAutomower}->{language};	
		}
	}
	
	elsif( $attrName eq "mower" ) {
		if( $cmd eq "set" ) {
			$hash->{HusqvarnaAutomower}->{mower} = $attrVal;
		    Log3 $name, 3, "$name - mower set to " . $hash->{HusqvarnaAutomower}->{mower};	
		}
		elsif( $cmd eq "del" ) {
            $hash->{HusqvarnaAutomower}->{mower} = 0;
            Log3 $name, 3, "$name - deleted mower and set to default: 0";
        }
	}

	elsif( $attrName eq "interval" ) {
        if( $cmd eq "set" ) {
            return "Interval must be greater than 0"
            unless($attrVal > 0);
            $hash->{HusqvarnaAutomower}->{interval} = $attrVal;
            RemoveInternalTimer($hash);
            InternalTimer( time() + $hash->{HusqvarnaAutomower}->{interval}, "HusqvarnaAutomower_DoUpdate", $hash, 0 );
            Log3 $name, 3, "$name - set interval: $attrVal";
        }

        elsif( $cmd eq "del" ) {
            $hash->{HusqvarnaAutomower}->{interval} = 300;
            RemoveInternalTimer($hash);
            InternalTimer( time() + $hash->{HusqvarnaAutomower}->{interval}, "HusqvarnaAutomower_DoUpdate", $hash, 0 );
            Log3 $name, 3, "$name - deleted interval and set to default: 300";
        }
    }

    return undef;
}


sub HusqvarnaAutomower_Undef($$){
	my ( $hash, $arg )  = @_;
    my $name            = $hash->{NAME};
    my $deviceId        = $hash->{DEVICEID};
    delete $modules{HusqvarnaAutomower}{defptr}{$deviceId};
    RemoveInternalTimer($hash);
    return undef;
}


sub HusqvarnaAutomower_Set($@){
	my ($hash,@a) = @_;
    return "\"set $hash->{NAME}\" needs at least an argument" if ( @a < 2 );
    my ($name,$setName,$setVal,$setVal2,$setVal3) = @a;

	Log3 $name, 3, "$name: set called with $setName " . ($setVal ? $setVal : "") if ($setName ne "?");

	if (HusqvarnaAutomower_CONNECTED($hash) eq 'disabled' && $setName !~ /clear/) {
        return "Unknown argument $setName, choose one of clear:all,readings";
        Log3 $name, 3, "$name: set called with $setName but device is disabled!" if ($setName ne "?");
        return undef;
    }
    
    if ($setName !~ /start3h|start6h|start9h|startTimer|stop|park|parkTimer|update/) {
        return "Unknown argument $setName, choose one of start3h start6h start9h startTimer stop park parkTimer update";
	} else {
        Log3 $name, 3, "$name: set $setName";
    }
	
	if ($setName eq 'update') {
        RemoveInternalTimer($hash);
        HusqvarnaAutomower_DoUpdate($hash);
    }
    
	if (HusqvarnaAutomower_CONNECTED($hash)) {
        	HusqvarnaAutomower_CMD($hash,$setName);        	
	}
	
    return undef;

}


##############################################################
#
# API AUTHENTICATION
#
##############################################################

sub HusqvarnaAutomower_APIAuth($) {
    my ($hash, $def) = @_;
    my $name = $hash->{NAME};
    
    my $username = $hash->{HusqvarnaAutomower}->{username};
    my $password = $hash->{HusqvarnaAutomower}->{password};
    
    my $header = "Content-Type: application/json\r\nAccept: application/json";
    my $json = '	{
    		"data" : {
    			"type" : "token",
    			"attributes" : {
    				"username" : "' . $username. '",
    				"password" : "' . $password. '"
    			}
    		}
    	}';

    HttpUtils_NonblockingGet({
        url        	=> AUTHURL . "token",
        timeout    	=> 5,
        hash       	=> $hash,
        method     	=> "POST",
        header     	=> $header,  
		data 		=> $json,
        callback   	=> \&HusqvarnaAutomower_APIAuthResponse,
    });  
    
}


sub HusqvarnaAutomower_APIAuthResponse($) {
    my ($param, $err, $data) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};

    if($err ne "") {
	    HusqvarnaAutomower_CONNECTED($hash,'error');
        Log3 $name, 2, "error while requesting ".$param->{url}." - $err";     
                                           
    } elsif($data ne "") {
   
        my $result = eval { decode_json($data) };
        if ($@) {
            Log3( $name, 2, " - JSON error while request: $@");
            return;
        }
	        
	    if ($result->{errors}) {
		    HusqvarnaAutomower_CONNECTED($hash,'error');
		    Log3 $name, 2, "Error: " . $result->{errors}[0]->{detail};
		    
	    } else {
	        Log3 $name, 2, "$data"; 

			$hash->{HusqvarnaAutomower}->{token} = $result->{data}{id};
			$hash->{HusqvarnaAutomower}->{provider} = $result->{data}{attributes}{provider};
			$hash->{HusqvarnaAutomower}->{user_id} = $result->{data}{attributes}{user_id};
			$hash->{HusqvarnaAutomower}->{expires} = time() + $result->{data}{attributes}{expires_in};
			
			# set Readings	
			readingsBeginUpdate($hash);
			readingsBulkUpdate($hash,'token',$hash->{HusqvarnaAutomower}->{token} );
			readingsBulkUpdate($hash,'provider',$hash->{HusqvarnaAutomower}->{provider} );
			readingsBulkUpdate($hash,'user_id',$hash->{HusqvarnaAutomower}->{user_id} );
			
			my $expire_date = strftime("%Y-%m-%d %H:%M:%S", localtime($hash->{HusqvarnaAutomower}->{expires}));
			readingsBulkUpdate($hash,'expires',$expire_date );
			readingsEndUpdate($hash, 1);
			
			HusqvarnaAutomower_CONNECTED($hash,'authenticated');

	    }
        
    }

}


sub HusqvarnaAutomower_CONNECTED($@) {
	my ($hash,$set) = @_;
    if ($set) {
	   $hash->{HusqvarnaAutomower}->{CONNECTED} = $set;
       RemoveInternalTimer($hash);
       %{$hash->{updateDispatch}} = ();
       if (!defined($hash->{READINGS}->{state}->{VAL}) || $hash->{READINGS}->{state}->{VAL} ne $set) {
       		readingsSingleUpdate($hash,"state",$set,1);
       }
	   return undef;
	} else {
		if ($hash->{HusqvarnaAutomower}->{CONNECTED} eq 'disabled') {
            return 'disabled';
        }
        elsif ($hash->{HusqvarnaAutomower}->{CONNECTED} eq 'connected') {
            return 1;
        } else {
            return 0;
        }
	}
}

##############################################################
#
# UPDATE FUNCTIONS
#
##############################################################

sub HusqvarnaAutomower_DoUpdate($) {
    my ($hash) = @_;
    my ($name,$self) = ($hash->{NAME},HusqvarnaAutomower_Whoami());

    Log3 $name, 5, "doUpdate() called.";

    if (HusqvarnaAutomower_CONNECTED($hash) eq "disabled") {
        Log3 $name, 3, "$name - Device is disabled.";
        return undef;
    }

	if (time() >= $hash->{HusqvarnaAutomower}->{expires} ) {
		Log3 $name, 2, "LOGIN TOKEN MISSING OR EXPIRED";
		HusqvarnaAutomower_CONNECTED($hash,'disconnected');

	} elsif ($hash->{HusqvarnaAutomower}->{CONNECTED} eq 'connected') {
		Log3 $name, 4, "Update with device: " . $hash->{HusqvarnaAutomower}->{mower_id};
		HusqvarnaAutomower_getMowerStatus($hash);
        InternalTimer( time() + $hash->{HusqvarnaAutomower}->{interval}, $self, $hash, 0 );

	} 

}




##############################################################
#
# GET MOWERS
#
##############################################################

sub HusqvarnaAutomower_getMower($) {
	my ($hash) = @_;
    my ($name) = $hash->{NAME};

	my $token = $hash->{HusqvarnaAutomower}->{token};
	my $provider = $hash->{HusqvarnaAutomower}->{provider};
	my $header = "Content-Type: application/json\r\nAccept: application/json\r\nAuthorization: Bearer " . $token . "\r\nAuthorization-Provider: " . $provider;

	HttpUtils_NonblockingGet({
        url        	=> APIURL . "mowers",
        timeout    	=> 5,
        hash       	=> $hash,
        method     	=> "GET",
        header     	=> $header,  
        callback   	=> \&HusqvarnaAutomower_getMowerResponse,
    });  
	
	return undef;
}


sub HusqvarnaAutomower_getMowerResponse($) {
	
	my ($param, $err, $data) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};

    if($err ne "") {
        Log3 $name, 2, "error while requesting ".$param->{url}." - $err";     
                                           
    } elsif($data ne "") {
	    
		if ($data eq "[]") {
		    Log3 $name, 2, "Please register an automower first";
		    $hash->{HusqvarnaAutomower}->{mower_id} = "none";

		    # STATUS LOGGEDIN MUST BE REMOVED
			HusqvarnaAutomower_CONNECTED($hash,'connected');

		} else {

		    Log3 $name, 5, "Automower(s) found"; 			
			Log3 $name, 5, $data; 
			
	        my $result = eval { decode_json($data) };
            if ($@) {
                Log3( $name, 2, " - JSON error while request: $@");
                return;
            }	
            		
			my $mower = $hash->{HusqvarnaAutomower}->{mower};
			Log3 $name, 5, $result->[$mower]->{'name'};
		    
			# MOWER DATA
			my $mymower = $result->[$mower];
			$hash->{HusqvarnaAutomower}->{mower_id} = $mymower->{'id'};
			$hash->{HusqvarnaAutomower}->{mower_name} = $mymower->{'name'};
			$hash->{HusqvarnaAutomower}->{mower_model} = $mymower->{'model'};

			# MOWER STATUS
		    my $mymowerStatus = $mymower->{'status'};
			$hash->{HusqvarnaAutomower}->{mower_battery} = $mymowerStatus->{'batteryPercent'};
			$hash->{HusqvarnaAutomower}->{mower_activity} = $mymowerStatus->{'mowerStatus'}->{'activity'};
			$hash->{HusqvarnaAutomower}->{mower_state} = $mymowerStatus->{'mowerStatus'}->{'state'};
			$hash->{HusqvarnaAutomower}->{mower_mode} = $mymowerStatus->{'operatingMode'};
		
			$hash->{HusqvarnaAutomower}->{mower_nextStart} = HusqvarnaAutomower_Correct_Localtime( $mymowerStatus->{'nextStartTimestamp'} );

			# MOWER capabilities
			my $mymowerCapabilities = $mymower->{'capabilities'};
			$hash->{HusqvarnaAutomower}->{mower_geofence} = $mymowerCapabilities->{'geofence'};
			$hash->{HusqvarnaAutomower}->{mower_headlights} = $mymowerCapabilities->{'headlights'};
			$hash->{HusqvarnaAutomower}->{mower_searchChargingStation} = $mymowerCapabilities->{'searchChargingStation'};
			$hash->{HusqvarnaAutomower}->{mower_fota} = $mymowerCapabilities->{'fota'};
			$hash->{HusqvarnaAutomower}->{mower_gpsNavigation} = $mymowerCapabilities->{'gpsNavigation'};
			$hash->{HusqvarnaAutomower}->{mower_weatherTimer} = $mymowerCapabilities->{'weatherTimer'};
			$hash->{HusqvarnaAutomower}->{mower_corridorWidth} = $mymowerCapabilities->{'corridorWidth'};

			HusqvarnaAutomower_CONNECTED($hash,'connected');

		}
		
		readingsBeginUpdate($hash);
		readingsBulkUpdate($hash, "mower_id", $hash->{HusqvarnaAutomower}->{mower_id} );    
		readingsBulkUpdate($hash, "mower_name", $hash->{HusqvarnaAutomower}->{mower_name} );    
		readingsBulkUpdate($hash, "mower_battery", $hash->{HusqvarnaAutomower}->{mower_battery} );    
		readingsBulkUpdate($hash, "batteryPercent", $hash->{HusqvarnaAutomower}->{mower_battery} );    
		readingsBulkUpdate($hash, "mower_activity", $hash->{HusqvarnaAutomower}->{mower_activity} );    
		readingsBulkUpdate($hash, "mower_state", $hash->{HusqvarnaAutomower}->{mower_state} ); 
		readingsBulkUpdate($hash, "mower_mode", HusqvarnaAutomower_ToGerman($hash, $hash->{HusqvarnaAutomower}->{mower_mode} ));    

		my $nextStartTimestamp = strftime("%Y-%m-%d %H:%M:%S", localtime($hash->{HusqvarnaAutomower}->{mower_nextStart}) );
		readingsBulkUpdate($hash, "mower_nextStart", $nextStartTimestamp );

		readingsBulkUpdate($hash, "mower_geofence", $hash->{HusqvarnaAutomower}->{mower_geofence} );
		readingsBulkUpdate($hash, "mower_headlights", $hash->{HusqvarnaAutomower}->{mower_headlights} );
		readingsBulkUpdate($hash, "mower_searchChargingStation", $hash->{HusqvarnaAutomower}->{mower_searchChargingStation} );
		readingsBulkUpdate($hash, "mower_fota", $hash->{HusqvarnaAutomower}->{mower_fota} );
		readingsBulkUpdate($hash, "mower_gpsNavigation", $hash->{HusqvarnaAutomower}->{mower_gpsNavigation} );
		readingsBulkUpdate($hash, "mower_weatherTimer", $hash->{HusqvarnaAutomower}->{mower_weatherTimer} );
		readingsBulkUpdate($hash, "mower_corridorWidth", $hash->{HusqvarnaAutomower}->{mower_corridorWidth} );  
		  
		readingsEndUpdate($hash, 1);
 	    
	}	
	
	return undef;

}


sub HusqvarnaAutomower_getMowerStatus($) {
	my ($hash) = @_;
    my ($name) = $hash->{NAME};

	my $token = $hash->{HusqvarnaAutomower}->{token};
	my $provider = $hash->{HusqvarnaAutomower}->{provider};
	my $header = "Content-Type: application/json\r\nAccept: application/json\r\nAuthorization: Bearer " . $token . "\r\nAuthorization-Provider: " . $provider;

	my $mymower_id = $hash->{HusqvarnaAutomower}->{mower_id};

	HttpUtils_NonblockingGet({
        url        	=> APIURL . "mowers/" . $mymower_id . "/status",
        timeout    	=> 5,
        hash       	=> $hash,
        method     	=> "GET",
        header     	=> $header,  
        callback   	=> \&HusqvarnaAutomower_getMowerStatusResponse,
    });  
	
	return undef;
}

sub HusqvarnaAutomower_getMowerStatusResponse($) {
	
	my ($param, $err, $data) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};

    if($err ne "") {
        Log3 $name, 2, "error while requesting ".$param->{url}." - $err";     
                                           
    } elsif($data ne "") {
	    
		Log3 $name, 5, $data; 
        my $result = eval { decode_json($data) };
        if ($@) {
            Log3( $name, 2, " - JSON error while request: $@");
            return;
        }
		        
		$hash->{HusqvarnaAutomower}->{mower_battery} = $result->{'batteryPercent'};
		$hash->{HusqvarnaAutomower}->{mower_activity} = HusqvarnaAutomower_ToGerman($hash, $result->{'mowerStatus'}->{'activity'});
		$hash->{HusqvarnaAutomower}->{mower_state} = HusqvarnaAutomower_ToGerman($hash, $result->{'mowerStatus'}->{'state'});
		$hash->{HusqvarnaAutomower}->{mower_mode} = HusqvarnaAutomower_ToGerman($hash, $result->{'operatingMode'});

		$hash->{HusqvarnaAutomower}->{mower_nextStart} = HusqvarnaAutomower_Correct_Localtime( $result->{'nextStartTimestamp'} );
		
		$hash->{HusqvarnaAutomower}->{mower_nextStartSource} = HusqvarnaAutomower_ToGerman($hash, $result->{'nextStartSource'});
		$hash->{HusqvarnaAutomower}->{mower_restrictedReason} = HusqvarnaAutomower_ToGerman($hash, $result->{'mowerStatus'}->{'restrictedReason'});
		
		$hash->{HusqvarnaAutomower}->{mower_cuttingMode} = HusqvarnaAutomower_ToGerman($hash, $result->{'mowerStatus'}->{'mode'});
		
		$hash->{HusqvarnaAutomower}->{mower_lastLatitude} = $result->{'lastLocations'}->[0]->{'latitude'};
		$hash->{HusqvarnaAutomower}->{mower_lastLongitude} = $result->{'lastLocations'}->[0]->{'longitude'};

		$hash->{HusqvarnaAutomower}->{mower_connected} = $result->{'connected'};
		my $lastErrorCode = HusqvarnaAutomower_errormapping( $result->{'lastErrorCode'});
		$hash->{HusqvarnaAutomower}->{mower_lastErrorCode} = $lastErrorCode->{ $hash->{HusqvarnaAutomower}->{language} } ;
		$hash->{HusqvarnaAutomower}->{mower_lastErrorCodeTimestamp} = HusqvarnaAutomower_Correct_Localtime( $result->{'lastErrorCodeTimestamp'} );
		$hash->{HusqvarnaAutomower}->{mower_errorConfirmable} = $result->{'errorConfirmable'};


		readingsBeginUpdate($hash);
		
		readingsBulkUpdate($hash, "mower_battery", $hash->{HusqvarnaAutomower}->{mower_battery}."%" );    
		readingsBulkUpdate($hash, "batteryPercent", $hash->{HusqvarnaAutomower}->{mower_battery} );    
		readingsBulkUpdate($hash, "mower_activity", $hash->{HusqvarnaAutomower}->{mower_activity} );    
		readingsBulkUpdate($hash, "mower_state", $hash->{HusqvarnaAutomower}->{mower_state} );  
		readingsBulkUpdate($hash, "mower_mode", $hash->{HusqvarnaAutomower}->{mower_mode} );  

		my $nextStartTimestamp = strftime("%Y-%m-%d %H:%M", localtime($hash->{HusqvarnaAutomower}->{mower_nextStart}));
		if ($nextStartTimestamp le "1999-12-31 00:00") { $nextStartTimestamp = "-"; }
		
		if (
			strftime("%Y-%m-%d", localtime($hash->{HusqvarnaAutomower}->{mower_nextStart}) )
			eq
			strftime("%Y-%m-%d", localtime() )
		) {
			$nextStartTimestamp = HusqvarnaAutomower_ToGerman($hash, "Today at") . " " . strftime("%H:%M", localtime($hash->{HusqvarnaAutomower}->{mower_nextStart}));

		} elsif (
			strftime("%Y-%m-%d", localtime($hash->{HusqvarnaAutomower}->{mower_nextStart}) )
			eq
			strftime("%Y-%m-%d", localtime(time + 86400) )
		) {
			$nextStartTimestamp = HusqvarnaAutomower_ToGerman($hash, "Tomorrow at") . " " . strftime("%H:%M", localtime($hash->{HusqvarnaAutomower}->{mower_nextStart}));

		} elsif ($nextStartTimestamp ne "-") {
			my @c_time = split(" ", $nextStartTimestamp);
			my $c_date = join("." => reverse split('-', (split(' ',$nextStartTimestamp))[0]));
			$nextStartTimestamp = $c_date . " " . HusqvarnaAutomower_ToGerman($hash, "at") . " " . $c_time[1];
			
		}
		readingsBulkUpdate($hash, "mower_nextStart", $nextStartTimestamp );  
		
  		readingsBulkUpdate($hash, "mower_nextStartSource", $hash->{HusqvarnaAutomower}->{mower_nextStartSource} );    
  		readingsBulkUpdate($hash, "mower_restrictedReason", $hash->{HusqvarnaAutomower}->{mower_restrictedReason} );    
  		readingsBulkUpdate($hash, "mower_cuttingMode", $hash->{HusqvarnaAutomower}->{mower_cuttingMode} );    

		readingsBulkUpdate($hash, "mower_lastLatitude", $hash->{HusqvarnaAutomower}->{mower_lastLatitude} );    
		readingsBulkUpdate($hash, "mower_lastLongitude", $hash->{HusqvarnaAutomower}->{mower_lastLongitude} ); 

		readingsBulkUpdate($hash, "mower_connected", $hash->{HusqvarnaAutomower}->{mower_connected} );    
		readingsBulkUpdate($hash, "mower_lastErrorCode", $hash->{HusqvarnaAutomower}->{mower_lastErrorCode} );
		my $lastErrorCodeTimestamp = strftime("%Y-%m-%d %H:%M", localtime( $hash->{HusqvarnaAutomower}->{mower_lastErrorCodeTimestamp} ));   
		if ($lastErrorCodeTimestamp le "1999-12-31 00:00") { $lastErrorCodeTimestamp = "-"; } 
		readingsBulkUpdate($hash, "mower_lastErrorCodeTimestamp", $lastErrorCodeTimestamp );  
		readingsBulkUpdate($hash, "mower_errorConfirmable", $hash->{HusqvarnaAutomower}->{mower_errorConfirmable} );    
		
		readingsEndUpdate($hash, 1);
	    
	}	
	
	return undef;

}


##############################################################
#
# SEND COMMAND
#
##############################################################

sub HusqvarnaAutomower_CMD($$) {
    my ($hash,$cmd) = @_;
    my $name = $hash->{NAME};
    
    my $token = $hash->{HusqvarnaAutomower}->{token};
	my $provider = $hash->{HusqvarnaAutomower}->{provider};
    my $mower_id = $hash->{HusqvarnaAutomower}->{mower_id};

    my $json = {};
    my $cmdURL = '';
    
	my $header = "Content-Type: application/json\r\nAccept: application/json\r\nAuthorization: Bearer " . $token . "\r\nAuthorization-Provider: " . $provider;
    
    Log3 $name, 5, "cmd: " . $cmd; 

    if      ($cmd eq "start3h")     { $cmdURL = "start/override/period"; $json = '{"period": 180}'; }
    elsif   ($cmd eq "start6h")     { $cmdURL = "start/override/period"; $json = '{"period": 360}'; }
    elsif   ($cmd eq "start9h")     { $cmdURL = "start/override/period"; $json = '{"period": 540}'; }
    elsif   ($cmd eq "startTimer")  { $cmdURL = "start"; }
    elsif   ($cmd eq "stop")        { $cmdURL = "pause"; }
    elsif   ($cmd eq "park")        { $cmdURL = "park"; }
    elsif   ($cmd eq "parkTimer")   { $cmdURL = "park/duration/timer"; }
	elsif 	($cmd eq "update")	{ return; }

    HttpUtils_NonblockingGet({
        url        	=> APIURL . "mowers/". $mower_id . "/control/" . $cmdURL,
        timeout    	=> 5,
        hash       	=> $hash,
        method     	=> "POST",
        header     	=> $header,
		data 		=> $json,
        callback   	=> \&HusqvarnaAutomower_CMDResponse,
    });  
    
}


sub HusqvarnaAutomower_CMDResponse($) {
    my ($param, $err, $data) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};

    if($err ne "") {
	    HusqvarnaAutomower_CONNECTED($hash,'error');
        Log3 $name, 2, "error while requesting ".$param->{url}." - $err";     
                                           
    } elsif($data ne "") {
        
	    my $result = eval { decode_json($data) };
        if ($@) {
            Log3( $name, 2, " - JSON error while request: $@");
            return;
        }

	    if ($result->{errors}) {
		    HusqvarnaAutomower_CONNECTED($hash,'error');
		    Log3 $name, 2, "Error: " . $result->{errors}[0]->{detail};
		    $hash->{HusqvarnaAutomower}->{mower_commandStatus} = $result->{errors}[0]->{detail};

	    } else {
	        Log3 $name, 3, $data; 
            $hash->{HusqvarnaAutomower}->{mower_commandStatus} = $result->{status} . " ". $result->{errorCode};

	    }

	    readingsSingleUpdate($hash, 'mower_commandStatus', $hash->{HusqvarnaAutomower}->{mower_commandStatus} ,1);
        
    }

}


###############################################################################

sub HusqvarnaAutomower_Correct_Localtime($) {
	
	my ($time) = @_;
	my ($dst) = (localtime)[8]; # fetch daylight savings time flag

	if ($dst) {
		return $time - ( 2 * 3600 );
	} else {
		return $time - ( 1 * 3600 );
	}
	
}


sub HusqvarnaAutomower_ToGerman($$) {
	my ($hash,$readingValue) = @_;
	my $name = $hash->{NAME};
	
	my %langGermanMapping = (
		#'initialized'					=> 'initialisiert',
		#'authenticated'					=> 'authentifiziert',
		#'disabled'						=> 'deaktiviert',
		#'connected'						=> 'verbunden',

		'Today at'                      =>	'Heute um',
		'Tomorrow at'                   =>	'Morgen um',
		'at'                            =>	'um',

		'NO_SOURCE'                     =>	'keine Quelle',
		'NOT_APPLICABLE'                =>	'undefiniert',
		
		'AUTO'                          =>  'automatisch',
		'MAIN_AREA'                     =>  'Hauptbereich',
		
		'MOWING'                        =>	'mäht',
		'CHARGING'                      =>	'lädt',
		
		'LEAVING'                       =>  'verlässt Ladestation',
		'GOING_HOME'                    => 	'fährt zur Ladestation',
		'WEEK_TIMER'                    => 	'Wochen-Zeitplan',
		'WEEK_SCHEDULE'                 => 	'Wochen-Zeitplan',
		
		'PARKED_IN_CS'                  =>  'geparkt',
		'COMPLETED_CUTTING_TODAY_AUTO'  =>  'Wetter-Timer',
		'PAUSED'                        =>  'pausiert',

		'SENSOR'                        =>  'Sensor',

        'OFF_DISABLED'                  =>  'ausgeschaltet',
        'OFF_HATCH_OPEN'                =>  'Abdeckung ist offen',
        'OFF_HATCH_CLOSED'              =>  'Ausgeschaltet, manueller Start erforderlich',

        'PARKED_TIMER'                  =>  'geparkt nach Zeitplan',
        'PARKED_PARK_SELECTED'          =>  'geparkt',

		'MOWER_CHARGING'                =>	'Automower lädt',

		'OK_SEARCHING'                  =>  'sucht Ladestation',
		'OK_LEAVING'                    =>  'verlässt Ladestation',
		'OK_CHARGING'                   =>  'lädt',
		'OK_CUTTING'                    =>  'mäht',
        'OK_CUTTING_TIMER_OVERRIDDEN'   =>  'manuelles Mähen',

        'HOME'                          =>	'home',
		'IN_OPERATION'                  =>	'aktiv',
		'RESTRICTED'                    =>	'inaktiv',

		'OK'                            =>  'OK',

	);
    
    if( defined($langGermanMapping{$readingValue}) and  HusqvarnaAutomower_isSetGerman($hash) ) {
        return $langGermanMapping{$readingValue};
    } else {
        return $readingValue;
    }
}

sub HusqvarnaAutomower_isSetGerman($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	if ( AttrVal('global','language','EN') eq 'DE' or $hash->{HusqvarnaAutomower}->{language} eq 'DE') {
		return 1;
	} else {
		return 0;
	}
}

sub HusqvarnaAutomower_Whoami()  { return (split('::',(caller(1))[3]))[1] || ''; }
sub HusqvarnaAutomower_Whowasi() { return (split('::',(caller(2))[3]))[1] || ''; }

sub HusqvarnaAutomower_errormapping($) {
	my ($Enummer) = @_;

		my %ErrorMapping = (
		'0'   =>	{
						'EN' => 'Unexpected error',
						'DE' => 'Unerwarteter Fehler',
					},
		'1'   =>  {
						'EN' => 'Outside working area',
						'DE' => 'Außerhalb des Arbeitsbereichs',
					},
		'2'   =>  {
						'EN' => 'No loop signal',
						'DE' => 'Kein Schleifensignal',
					},
		'3'   =>  {
						'EN' => 'Wrong loop signal',
						'DE' => 'Falsches Schleifensignal',
					},
		'4'   =>  {
						'EN' => 'Loop sensor problem, front',
						'DE' => 'Schleifensensorproblem, vorne',
					},
		'5'   =>  {
						'EN' => 'Loop sensor problem, rear',
						'DE' => 'Schleifensensor Problem, hinten',
					},
		'6'   =>  {
						'EN' => 'Loop sensor problem, left',
						'DE' => 'Schleifensensorproblem, links',
					},
		'7'   =>  {
						'EN' => 'Loop sensor problem, right',
						'DE' => 'Schleifensensorproblem, rechts',
					},
		'8'   =>  {
						'EN' => 'Wrong PIN code',
						'DE' => 'Falscher PIN-Code',
					},
		'9'   =>  {
						'EN' => 'Trapped',
						'DE' => 'Gefangen',
					},
		'10'   =>  {
						'EN' => 'Upside down',
						'DE' => 'Kopfüber',
					},
		'11'   =>  {
						'EN' => 'Low battery',
						'DE' => 'Niedriger Batteriestatus',
					},
		'12'   =>  {
						'EN' => 'Empty battery',
						'DE' => 'Batterie leer',
					},
		'13'   =>  {
						'EN' => 'No drive',
						'DE' => 'kein Antrieb',
					},
		'14'   =>  {
						'EN' => 'Mower lifted',
						'DE' => 'Mäher angehoben',
					},
		'15'   =>  {
						'EN' => 'Lifted',
						'DE' => 'angehoben',
					},
		'16'   =>  {
						'EN' => 'Stuck in charging station',
						'DE' => 'In der Ladestation stecken',
					},
		'17'   =>  {
						'EN' => 'Charging station blocked',
						'DE' => 'Ladestation blockiert',
					},
		'18'   =>  {
						'EN' => 'Collision sensor problem, rear',
						'DE' => 'Kollisionssensor Problem, hinten',
					},
		'19'   =>  {
						'EN' => 'Collision sensor problem, front',
						'DE' => 'Kollisionssensor Problem, vorn',
					},
		'20'   =>  {
						'EN' => 'Wheel motor blocked, right',
						'DE' => 'Kollisionssensor Problem, rechts',
					},
		'21'   =>  {
						'EN' => 'Wheel motor blocked, left',
						'DE' => 'Kollisionssensor Problem, links',
					},
		'22'   =>  {
						'EN' => 'Wheel drive problem, right',
						'DE' => 'Radantriebsproblem rechts',
					},
		'23'   =>  {
						'EN' => 'Wheel drive problem, left',
						'DE' => 'Radantriebsproblem links',
					},
		'24'   =>  {
						'EN' => 'Cutting system blocked',
						'DE' => 'Schneidsystem blockiert',
					},
		'25'   =>  {
						'EN' => 'Cutting system blocked',
						'DE' => 'Schneidsystem blockiert',
					},
		'26'   =>  {
						'EN' => 'Invalid sub-device combination',
						'DE' => 'Ungültige Subgerätekombination',
					},
		'27'   =>  {
						'EN' => 'Settings restored',
						'DE' => 'Einstellungen wiederhergestellt',
					},
		'28'   =>  {
						'EN' => 'Memory circuit problem',
						'DE' => 'Speicherproblem',
					},
		'29'   =>  {
						'EN' => 'Slope too steep',
						'DE' => 'Hang zu steil',
					},
		'30'   =>  {
						'EN' => 'Charging system problem',
						'DE' => 'Problem mit dem Ladesystem',
					},
		'31'   =>  {
						'EN' => 'STOP button problem',
						'DE' => 'STOP-Taste Problem',
					},
		'32'   =>  {
						'EN' => 'Tilt sensor problem',
						'DE' => 'Problem mit dem Neigungssensor',
					},
		'33'   =>  {
						'EN' => 'Mower tilted',
						'DE' => 'Mäher gekippt',
					},
		'34'   =>  {
						'EN' => 'Cutting stopped - slope too steep',
						'DE' => 'Schnitt gestoppt - Gefälle zu steil',
					},
		'35'   =>  {
						'EN' => 'Wheel motor overloaded, right',
						'DE' => 'Radmotor rechts überlastet',
					},
		'36'   =>  {
						'EN' => 'Wheel motor overloaded, left',
						'DE' => 'Radmotor links überlastet',
					},
		'37'   =>  {
						'EN' => 'Charging current too high',
						'DE' => 'Ladestrom zu hoch',
					},
		'38'   =>  {
						'EN' => 'Electronic problem',
						'DE' => 'Elektronisches Problem',
					},
		'39'   =>  {
						'EN' => 'Cutting motor problem',
						'DE' => 'Schneidmotorproblem',
					},
		'40'   =>  {
						'EN' => 'Limited cutting height range',
						'DE' => 'Begrenzter Schnitthöhenbereich',
					},
		'41'   =>  {
						'EN' => 'Unexpected cutting height adj',
						'DE' => 'Unerwartete Schnitthöhe',
					},
		'42'   =>  {
						'EN' => 'Limited cutting height range',
						'DE' => 'Begrenzter Schnitthöhenbereich',
					},
		'43'   =>  {
						'EN' => 'Cutting height problem, drive',
						'DE' => 'Schnitthöhenproblem, antrieb',
					},
		'44'   =>  {
						'EN' => 'Cutting height problem, curr',
						'DE' => 'Schnitthöhenproblem',
					},
		'45'   =>  {
						'EN' => 'Cutting height problem, dir',
						'DE' => 'Schnitthöhenproblem',
					},
		'46'   =>  {
						'EN' => 'Cutting height blocked',
						'DE' => 'Schnitthöhe blockiert',
					},
		'47'   =>  {
						'EN' => 'Cutting height problem',
						'DE' => 'Schnitthöhenproblem',
					},
		'48'   =>  {
						'EN' => 'No response from charger',
						'DE' => 'Keine Antwort vom Ladegerät',
					},
		'49'   =>  {
						'EN' => 'Ultrasonic problem',
						'DE' => 'Ultraschallproblem',
					},
		'50'   =>  {
						'EN' => 'Guide 1 not found',
						'DE' => 'Suchkabel 1 nicht gefunden',
					},
		'51'   =>  {
						'EN' => 'Guide 2 not found',
						'DE' => 'Suchkabel 2 nicht gefunden',
					},
		'52'   =>  {
						'EN' => 'Guide 3 not found',
						'DE' => 'Suchkabel 3 nicht gefunden',
					},
		'53'   =>  {
						'EN' => 'GPS navigation problem',
						'DE' => 'GPS-Navigationsproblem',
					},
		'54'   =>  {
						'EN' => 'Weak GPS signal',
						'DE' => 'Schwaches GPS-Signal',
					},
		'55'   =>  {
						'EN' => 'Difficult finding home',
						'DE' => 'Schwer nach Hause zu finden',
					},
		'56'   =>  {
						'EN' => 'Guide calibration accomplished',
						'DE' => 'Suchkabelkalibrierung abgeschlossen',
					},
		'57'   =>  {
						'EN' => 'Guide calibration failed',
						'DE' => 'Suchkabelkalibrierung fehlgeschlagen',
					},
		'58'   =>  {
						'EN' => 'Temporary battery problem',
						'DE' => 'Temporäres Batterieproblem',
					},
		'59'   =>  {
						'EN' => 'Temporary battery problem',
						'DE' => 'Temporäres Batterieproblem',
					},
		'60'   =>  {
						'EN' => 'Temporary battery problem',
						'DE' => 'Temporäres Batterieproblem',
					},
		'61'   =>  {
						'EN' => 'Temporary battery problem',
						'DE' => 'Temporäres Batterieproblem',
					},
		'62'   =>  {
						'EN' => 'Temporary battery problem',
						'DE' => 'Temporäres Batterieproblem',
					},
		'63'   =>  {
						'EN' => 'Temporary battery problem',
						'DE' => 'Temporäres Batterieproblem',
					},
		'64'   =>  {
						'EN' => 'Temporary battery problem',
						'DE' => 'Temporäres Batterieproblem',
					},
		'65'   =>  {
						'EN' => 'Temporary battery problem',
						'DE' => 'Temporäres Batterieproblem',
					},
		'66'   =>  {
						'EN' => 'Battery problem',
						'DE' => 'Batterieproblem',
					},
		'67'   =>  {
						'EN' => 'Battery problem',
						'DE' => 'Batterieproblem',
					},
		'68'   =>  {
						'EN' => 'Temporary battery problem',
						'DE' => 'Temporäres Batterieproblem',
					},
		'69'   =>  {
						'EN' => 'Alarm! Mower switched off',
						'DE' => 'Alarm! Mäher ausgeschaltet',
					},
		'70'   =>  {
						'EN' => 'Alarm! Mower stopped',
						'DE' => 'Alarm! Mäher angehalten',
					},
		'71'   =>  {
						'EN' => 'Alarm! Mower lifted',
						'DE' => 'Alarm! Mäher angehoben',
					},
		'72'   =>  {
						'EN' => 'Alarm! Mower tilted',
						'DE' => 'Alarm! Mäher gekippt',
					},
		'73'   =>  {
						'EN' => 'Alarm! Mower in motion',
						'DE' => 'Alarm! Mäher in Bewegung',
					},
		'74'   =>  {
						'EN' => 'Alarm! Outside geofence',
						'DE' => 'Alarm! Außerhalb Geofence',
					},
		'75'   =>  {
						'EN' => 'Connection changed',
						'DE' => 'Verbindung geändert',
					},
		'76'   =>  {
						'EN' => 'Connection NOT changed',
						'DE' => 'Verbindung NICHT geändert',
					},
		'77'   =>  {
						'EN' => 'Com board not available',
						'DE' => 'Com Board nicht verfügbar',
					},
		'78'   =>  {
						'EN' => 'Slipped - Mower has Slipped.Situation not solved with moving pattern',
						'DE' => 'Ausgerutscht - Mäher ist ausgerutscht. Situation nicht mit Bewegungsmuster gelöst',
					},
		'79'   =>  {
						'EN' => 'Invalid battery combination - Invalid combination of different battery types.',
						'DE' => 'Ungültige Batteriekombination - Ungültige Kombination verschiedener Batterietypen.',
					},
		'80'   =>  {
						'EN' => 'Cutting system imbalance    Warning',
						'DE' => 'Unwucht des Schneidsystems    Warnung',
					},
		'81'   =>  {
						'EN' => 'Safety function faulty',
						'DE' => 'Sicherheitsfunktion fehlerhaft',
					},
		'82'   =>  {
						'EN' => 'Wheel motor blocked, rear right',
						'DE' => 'Radmotor hinten rechts blockiert',
					},
		'83'   =>  {
						'EN' => 'Wheel motor blocked, rear left',
						'DE' => 'Radmotor hinten links blockiert',
					},
		'84'   =>  {
						'EN' => 'Wheel drive problem, rear right',
						'DE' => 'Problem mit dem Radantrieb hinten rechts',
					},
		'85'   =>  {
						'EN' => 'Wheel drive problem, rear left',
						'DE' => 'Problem mit dem Radantrieb hinten links',
					},
		'86'   =>  {
						'EN' => 'Wheel motor overloaded, rear right',
						'DE' => 'Radmotor hinten rechts überlastet',
					},
		'87'   =>  {
						'EN' => 'Wheel motor overloaded, rear left',
						'DE' => 'Radmotor hinten links überlastet',
					},
		'88'   =>  {
						'EN' => 'Angular sensor problem',
						'DE' => 'Winkelsensor Problem',
					},
		'89'   =>  {
						'EN' => 'Invalid system configuration',
						'DE' => 'Ungültige Systemkonfiguration',
					},
		'90'   =>  {
						'EN' => 'No power in charging station',
						'DE' => 'Kein Strom in der Ladestation',
					},
		);
	return $ErrorMapping{$Enummer};
	if( defined($ErrorMapping{$Enummer}) ) {
        return \%ErrorMapping{$Enummer};
    } else {
        return {
						'EN' => 'X',
						'DE' => 'X',
					};
    }
}

##############################################################

1;

=pod

=item device
=item summary    Modul to control Husqvarna Automower with Connect Module (SIM)
=item summary_DE Modul zur Steuerung von Husqvarna Automower mit Connect Modul (SIM)

=begin html

<a name="HusqvarnaAutomower"></a>
<h3>Husqvarna Automower with Connect Module (SIM)</h3>
<ul>
	<u><b>Requirements</b></u>
  	<br><br>
	<ul>
		<li>This module allows the communication between the Husqvarna Cloud and FHEM.</li>
		<li>You can control any Automower that is equipped with the original Husqvarna Connect Module (SIM).</li>
  		<li>The Automower must be registered in the Husqvarna App beforehand.</li>
  	</ul>
	<br>
	
	<a name="HusqvarnaAutomowerdefine"></a>
	<b>Define</b>
	<ul>
		<code>define &lt;name&gt; HusqvarnaAutomower</code>
		<br><br>
		Beispiel:
		<ul><br>
			<code>define myMower HusqvarnaAutomower<br>
			attr myMower username YOUR_USERNAME<br>
			attr myMower password YOUR_PASSWORD
			</code><br>
		</ul>
		<br><br>
		You must set both attributes <b>username</b> and <b>password</b>. These are the same that you use to login via the Husqvarna App.
	</ul>
	<br>
	
	<a name="HusqvarnaAutomowerSet"></a>
	<b>Set</b>
	<ul>
		<li>startTimer - Start with next timer (Caution: might not start mowing immdiately)</li>
		<li>start3h - Starts immediately for 3 hours</li>
        <li>start6h - Starts immediately for 6 hours</li>
		<li>start9h - Starts immediately for 9 hours</li>
		<li>stop - Stops/pauses mower immediately at current position</li>
        <li>park - Parks mower in charging station until further notice</li>
		<li>parkTimer - Parks mower in charging station and starts with next timer</li>
        <li>update - Updates the status</li>
	</ul>
	<br>
	
	<a name="HusqvarnaAutomowerattributes"></a>
	<b>Attributes</b>
	<ul>
		<li>username - Email that is used in Husqvarna App</li>
		<li>password - Password that is used in Husqvarna App</li>
	</ul>
	<br>
	
	<b>Optional attributes</b>
	<ul>
		<li>mower - ID of Automower, if more that one is registered. Default: 0</li>
		<li>interval - Time in seconds that is used to get new data from Husqvarna Cloud. Default: 300</li>
		<li>language - language setting, EN = original messages, DE = german translation. Default: DE</li>
	</ul>
	<br>
	
	<a name="HusqvarnaAutomowerreadings"></a>
	<b>Readings</b>
	<ul>
		<li>expires - date when session of Husqvarna Cloud expires</li>
		<li>batteryPercent - Battery power in percent</li>
		<li>mower_id - ID of the mower</li>
		<li>mower_battery - Battery power in percent</li>
        <li>mower_commandStatus - Status of the last sent command</li>
		<li>mower_lastLatitude - last known position (latitude)</li>
		<li>mower_lastLongitude - last known position (longitude)</li>
		<li>mower_mode - current working mode (e. g. AUTO)</li>
		<li>mower_name - name of the mower</li>
		<li>mower_nextStart - next start time</li>
		<li>mower_state - current status (e. g. OFF_HATCH_CLOSED_DISABLED, PARKED_IN_CS)</li>
		<li>mower_cuttingMode - mode of cutting area (e. g. MAIN_AREA)</li>
        <li>mower_nextStartSource - detailed status (e. g. COMPLETED_CUTTING_TODAY_AUTO)</li>
        <li>mower_restrictedReason - reason for parking (e. g. SENSOR)</li>
		<li>provider - should be Husqvarna</li>
		<li>state - status of connection to Husqvarna Cloud (e. g. connected)</li>
		<li>token - current session token of Husqvarna Cloud</li>
		<li>user_id - your user ID in Husqvarna Cloud</li>
	</ul>

</ul>

=end html



=begin html_DE

<a name="HusqvarnaAutomower"></a>
<h3>Husqvarna Automower mit Connect Modul</h3>
<ul>
	<u><b>Voraussetzungen</b></u>
	<br><br>
	<ul>
		<li>Dieses Modul ermöglicht die Kommunikation zwischen der Husqvarna Cloud und FHEM.</li>
		<li>Es kann damit jeder Automower, der über ein original Husqvarna Connect Modul (SIM) verfügt, überwacht und gesteuert werden.</li>
		<li>Der Automower muss vorab in der Husqvarna App eingerichtet sein.</li>
	</ul>
	<br>
	
	<a name="HusqvarnaAutomowerdefine"></a>
	<b>Define</b>
	<ul>
		<br>
		<code>define &lt;name&gt; HusqvarnaAutomower</code>
		<br><br>
		Beispiel:
		<ul><br>
			<code>define myMower HusqvarnaAutomower<br>
			attr myMower username YOUR_USERNAME<br>
			attr myMower password YOUR_PASSWORD
			</code><br>
		</ul>
		<br><br>
		Es müssen die beiden Attribute <b>username</b> und <b>password</b> gesetzt werden. Diese sind identisch mit den Logindaten der Husqvarna App.
	</ul>
	<br>
	
	<a name="HusqvarnaAutomowerSet"></a>
	<b>Set</b>
	<ul>
		<li>startTimer - Startet mit dem nächsten Timer</li>
		<li>start3h - Startet sofort für 3 Stunden</li>
        <li>start6h - Startet sofort für 6 Stunden</li>
		<li>start9h - Startet sofort für 9 Stunden</li>
		<li>stop - Stoppt/pausiert den Mäher sofort an der aktuellen Position</li>
        <li>park - Parkt den Mäher in der Ladestation bis auf Weiteres</li>
		<li>parkTimer - Parkt den Mäher in der Ladestation und startet mit dem nächsten Timer</li>
        <li>update - Aktualisiert den Status</li>
	</ul>
	<br>
  
  <a name="HusqvarnaAutomowerattributes"></a>
	<b>Attributes</b>
	<ul>
		<li>username - Email, die in der Husqvarna App verwendet wird</li>
		<li>password - Passwort, das in der Husqvarna App verwendet wird</li>
	</ul>
	<br>
	
	<b>Optionale Attribute</b>
	<ul>
		<li>mower - ID des Automowers, sofern mehrere registriert sind. Standard: 0</li>
		<li>interval - Zeit in Sekunden nach denen neue Daten aus der Husqvarna Cloud abgerufen werden. Standard: 300</li>
		<li>language - Spracheinstellungen, EN = original Meldungen, DE = deutsche Übersetzung. Standard: DE</li>
	</ul>
	<br>
	
	<a name="HusqvarnaAutomowerreadings"></a>
	<b>Readings</b>
	<ul>
		<li>expires - Datum wann die Session der Husqvarna Cloud abläuft</li>
        <li>batteryPercent - Batteryladung in Prozent (ohne %-Zeichen)</li>
        <li>mower_id - ID des Automowers</li>
		<li>mower_battery - Bettrieladung in Prozent (mit %-Zeichen)</li>
        <li>mower_commandStatus - Status des letzten uebermittelten Kommandos</li>
		<li>mower_lastLatitude - letzte bekannte Position (Breitengrad)</li>
		<li>mower_lastLongitude - letzte bekannte Position (Längengrad)</li>
		<li>mower_mode - aktueller Arbeitsmodus (e. g. AUTO)</li>
		<li>mower_name - Name des Automowers</li>
		<li>mower_nextStart - nächste Startzeit</li>
		<li>mower_state - aktueller Status (e. g. OFF_HATCH_CLOSED_DISABLED, PARKED_IN_CS)</li>
		<li>mower_cuttingMode - Angabe welcher Bereich gemäht wird (e. g. MAIN_AREA)</li>
        <li>mower_nextStartSource - detaillierter Status (e. g. COMPLETED_CUTTING_TODAY_AUTO)</li>
        <li>mower_restrictedReason - Grund für Parken (e. g. SENSOR)</li>
		<li>provider - Sollte immer Husqvarna sein</li>
		<li>state - Status der Verbindung zur Husqvarna Cloud (e. g. connected)</li>
		<li>token - aktueller Sitzungstoken für die Husqvarna Cloud</li>
		<li>user_id - Nutzer-ID in der Husqvarna Cloud</li>
	</ul>

</ul>


=end html_DE
