###############################################################################
# 
#  (c) 2018 Copyright: Dr. Dennis Krannich (blog at krannich dot de)
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
# $Id: 74_HusqvarnaAutomower.pm 0 2018-01-27 12:00:00Z krannich $
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

my $version = "0.1";

use constant AUTHURL => "https://iam-api.dss.husqvarnagroup.net/api/v3/";
use constant APIURL => "https://amc-api.dss.husqvarnagroup.net/v1/";

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
        HusqvarnaAutomower     => { 
            CONNECTED   			=> 0,
            version     			=> $version,
            token					=> '',
            provider				=> '',
            user_id					=> '',
            mower_id				=> '',
            mower_name				=> '',
            mower_model 			=> '',
            mower_batteryLevel 		=> 0,
            mower_status 		 	=> '',
            mower_lastLatitude 		=> 0,
            mower_lastLongitude 	=> 0,
            mower_status 		 	=> '',
            device_operatingMode 	=> '',
            mower_nextStart 		=> 0,
            mower 					=> 0,
            username 				=> '',
            password 				=> '',
            interval    			=> 300,
            expires 				=> time(),
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
            Log3 $name, 5, "$name - disabled";
        }

        elsif( $cmd eq "del" ) {
            readingsSingleUpdate ( $hash, "state", "active", 1 );
            Log3 $name, 5, "$name - enabled";
        }
    }
    
	elsif( $attrName eq "username" ) {
		if( $cmd eq "set" ) {
		    $hash->{HusqvarnaAutomower}->{username} = $attrVal;
		    Log3 $name, 5, "$name - username set to " . $hash->{HusqvarnaAutomower}->{username};
		}
	}

	elsif( $attrName eq "password" ) {
		if( $cmd eq "set" ) {
			$hash->{HusqvarnaAutomower}->{password} = $attrVal;
		    Log3 $name, 5, "$name - password set to " . $hash->{HusqvarnaAutomower}->{password};	
		}
	}
	
	elsif( $attrName eq "mower" ) {
		if( $cmd eq "set" ) {
			$hash->{HusqvarnaAutomower}->{mower} = $attrVal;
		    Log3 $name, 5, "$name - mower set to " . $hash->{HusqvarnaAutomower}->{mower};	
		}
		elsif( $cmd eq "del" ) {
            $hash->{HusqvarnaAutomower}->{mower}   = 0;
            Log3 $name, 5, "$name - deleted mower and set to default: 0";
        }

	}

	elsif( $attrName eq "interval" ) {
        if( $cmd eq "set" ) {
            RemoveInternalTimer($hash);
            return "Interval must be greater than 0"
            unless($attrVal > 0);
            $hash->{HusqvarnaAutomower}->{interval} = $attrVal;
            Log3 $name, 5, "$name - set interval: $attrVal";
        }

        elsif( $cmd eq "del" ) {
            RemoveInternalTimer($hash);
            $hash->{HusqvarnaAutomower}->{interval}   = 300;
            Log3 $name, 5, "$name - deleted interval and set to default: 300";
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

    if ($setName !~ /start|stop|pause|update/) {
        return "Unknown argument $setName, choose one of start stop pause update";
	}
	
	if ($setName eq 'update') {
        RemoveInternalTimer($hash);
        HusqvarnaAutomower_DoUpdate($hash);
    }
    
	if (HusqvarnaAutomower_CONNECTED($hash)) {

	    if ($setName eq 'start') {
		    
		    
	    } elsif ($setName eq 'stop') {
		    
		    
	    } elsif ($setName eq 'pause') {
		    
		    
	    }

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
        Log3 $name, 5, "error while requesting ".$param->{url}." - $err";     
                                           
    } elsif($data ne "") {
	    
	    my $result = decode_json($data);
	    if ($result->{errors}) {
		    HusqvarnaAutomower_CONNECTED($hash,'error');
		    Log3 $name, 5, "Error: " . $result->{errors}[0]->{detail};
		    
	    } else {
	        Log3 $name, 5, "$data"; 

			$hash->{HusqvarnaAutomower}->{token} = $result->{data}{id};
			$hash->{HusqvarnaAutomower}->{provider} = $result->{data}{attributes}{provider};
			$hash->{HusqvarnaAutomower}->{user_id} = $result->{data}{attributes}{user_id};
			$hash->{HusqvarnaAutomower}->{expires} = time() + $result->{data}{attributes}{expires_in};
			
			# set Readings	
			readingsBeginUpdate($hash);
			readingsBulkUpdate($hash,'token',$hash->{HusqvarnaAutomower}->{token} );
			readingsBulkUpdate($hash,'provider',$hash->{HusqvarnaAutomower}->{provider} );
			readingsBulkUpdate($hash,'user_id',$hash->{HusqvarnaAutomower}->{user_id} );
			readingsBulkUpdate($hash,'expires',$hash->{HusqvarnaAutomower}->{expires} );
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

    Log3 $name, 3, "doUpdate() called.";

    if (HusqvarnaAutomower_CONNECTED($hash) eq "disabled") {
        Log3 $name, 3, "$name - Device is disabled.";
        return undef;
    }

	if (time() >= $hash->{HusqvarnaAutomower}->{expires} ) {
		Log3 $name, 3, "LOGIN TOKEN MISSING OR EXPIRED";
		HusqvarnaAutomower_CONNECTED($hash,'disconnected');

	} elsif ($hash->{HusqvarnaAutomower}->{CONNECTED} eq 'connected') {
		Log3 $name, 3, "Update with device: " . $hash->{HusqvarnaAutomower}->{mower_id};
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
        Log3 $name, 5, "error while requesting ".$param->{url}." - $err";     
                                           
    } elsif($data ne "") {
	    
		if ($data eq "[]") {
		    Log3 $name, 3, "Please register an automower first";
		    $hash->{HusqvarnaAutomower}->{mower_id} = "none";

		    # STATUS LOGGEDIN MUST BE REMOVED
			HusqvarnaAutomower_CONNECTED($hash,'connected');

		} else {

		    Log3 $name, 5, "Automower(s) found"; 			
			Log3 $name, 5, $data; 
			
			my $result = decode_json($data);
			my $mower = $hash->{HusqvarnaAutomower}->{mower};
			Log3 $name, 5, $result->[$mower]->{'name'};
		    
			# MOWER DATA
			my $mymower = $result->[$mower];
			$hash->{HusqvarnaAutomower}->{mower_id} = $mymower->{'id'};
			$hash->{HusqvarnaAutomower}->{mower_name} = $mymower->{'name'};
			$hash->{HusqvarnaAutomower}->{mower_model} = $mymower->{'model'};

			# MOWER STATUS
		    my $mymowerStatus = $mymower->{'status'};
			$hash->{HusqvarnaAutomower}->{mower_battery} = $mymowerStatus->{'batteryLevel'};
			$hash->{HusqvarnaAutomower}->{mower_status} = $mymowerStatus->{'mowerStatus'};
			$hash->{HusqvarnaAutomower}->{mower_mode} = $mymowerStatus->{'operatingMode'};
			$hash->{HusqvarnaAutomower}->{mower_nextStart} = $mymowerStatus->{'nextStartTimestamp'};

			HusqvarnaAutomower_CONNECTED($hash,'connected');

		}
		
		readingsBeginUpdate($hash);
		#readingsBulkUpdate($hash,$reading,$value);
		readingsBulkUpdate($hash, "mower_id", $hash->{HusqvarnaAutomower}->{mower_id} );    
		readingsBulkUpdate($hash, "mower_name", $hash->{HusqvarnaAutomower}->{mower_name} );    
		readingsBulkUpdate($hash, "mower_battery", $hash->{HusqvarnaAutomower}->{mower_battery} );    
		readingsBulkUpdate($hash, "mower_status", $hash->{HusqvarnaAutomower}->{mower_status} );    
		readingsBulkUpdate($hash, "mower_mode", $hash->{HusqvarnaAutomower}->{mower_mode} );    
		readingsBulkUpdate($hash, "mower_nextStart", $hash->{HusqvarnaAutomower}->{mower_nextStart} );    
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
        Log3 $name, 5, "error while requesting ".$param->{url}." - $err";     
                                           
    } elsif($data ne "") {
	    
		Log3 $name, 5, $data; 
		my $result = decode_json($data);

		$hash->{HusqvarnaAutomower}->{mower_battery} = $result->{'batteryLevel'};
		$hash->{HusqvarnaAutomower}->{mower_status} = $result->{'mowerStatus'};
		$hash->{HusqvarnaAutomower}->{mower_mode} = $result->{'operatingMode'};
		$hash->{HusqvarnaAutomower}->{mower_nextStart} = $result->{'nextStartTimestamp'};
		$hash->{HusqvarnaAutomower}->{mower_lastLatitude} = $result->{'lastLocations'}->[0]->{'latitude'};
		$hash->{HusqvarnaAutomower}->{mower_lastLongitude} = $result->{'lastLocations'}->[0]->{'longitude'};

		readingsBeginUpdate($hash);
		#readingsBulkUpdate($hash,$reading,$value);
		readingsBulkUpdate($hash, "mower_battery", $hash->{HusqvarnaAutomower}->{mower_battery} );    
		readingsBulkUpdate($hash, "mower_status", $hash->{HusqvarnaAutomower}->{mower_status} );    
		readingsBulkUpdate($hash, "mower_mode", $hash->{HusqvarnaAutomower}->{mower_mode} );    
		readingsBulkUpdate($hash, "mower_nextStart", $hash->{HusqvarnaAutomower}->{mower_nextStart} );    
		readingsBulkUpdate($hash, "mower_lastLatitude", $hash->{HusqvarnaAutomower}->{mower_lastLatitude} );    
		readingsBulkUpdate($hash, "mower_lastLongitude", $hash->{HusqvarnaAutomower}->{mower_lastLongitude} );    
		readingsEndUpdate($hash, 1);
	    
	}	
	
	return undef;

}


##############################################################
#
# SEND COMMAND
#
##############################################################

sub HusqvarnaAutomower_CMD($) {
    my ($hash, $def) = @_;
    my $name = $hash->{NAME};
    
    # valid commands ['PARK', 'STOP', 'START']
    my $token = $hash->{HusqvarnaAutomower}->{token};
	my $provider = $hash->{HusqvarnaAutomower}->{provider};
    my $mower_id = $hash->{HusqvarnaAutomower}->{mower_id};

	my $header = "Content-Type: application/json\r\nAccept: application/json\r\nAuthorization: Bearer " . $token . "\r\nAuthorization-Provider: " . $provider;

    my $json = '{
    		"action": "START"
    }';

    HttpUtils_NonblockingGet({
        url        	=> APIURL . "mowers/". $mower_id . "/control",
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
        Log3 $name, 5, "error while requesting ".$param->{url}." - $err";     
                                           
    } elsif($data ne "") {
	    
	    my $result = decode_json($data);
	    if ($result->{errors}) {
		    HusqvarnaAutomower_CONNECTED($hash,'error');
		    Log3 $name, 5, "Error: " . $result->{errors}[0]->{detail};
		    
	    } else {
	        Log3 $name, 5, "$data"; 

			
	    }
        
    }

}


###############################################################################

sub HusqvarnaAutomower_Whoami()  { return (split('::',(caller(1))[3]))[1] || ''; }
sub HusqvarnaAutomower_Whowasi() { return (split('::',(caller(2))[3]))[1] || ''; }

##############################################################

1;

=pod

=item device
=item summary    Modul to control Husqvarna Automower with Connect Module
=item summary_DE Modul zur Steuerung von Husqvarna Automower mit Connect Modul

=begin html

<a name="HusqvarnaAutomower"></a>
<h3>Husqvarna Automower with Connect Module</h3>
<ul>
  <u><b>Voraussetzungen</b></u>
  <br><br>
  <li>Dieses FHEM Modul ermöglicht die Kommunikation zwischen der HusqvarnaCloud und FHEM. Es kann damit jeder Automower, das über ein original Husqvarna Connect-Modul verfügt, überwacht und gesteuert werden.</li>
  <li>Der Automower muss vorab in der Husqvarna App eingerichtet sein.</li>
</ul>


=end html

=begin html_DE

<a name="HusqvarnaAutomower"></a>
<h3>Husqvarna Automower mit Connect Modul</h3>
<ul>
	<u><b>Voraussetzungen</b></u>
	<br><br>
	Dieses FHEM Modul ermöglicht die Kommunikation zwischen der HusqvarnaCloud und FHEM.<br>
	Es kann damit jeder Automower, das über ein original Husqvarna Connect-Modul verfügt, überwacht und gesteuert werden.</li>
	<br>Der Automower muss vorab in der Husqvarna App eingerichtet sein.</li>
</ul>
<br>
<a name="HusqvarnaAutomowerdefine"></a>
<b>Define</b>
<ul><br>
	<code>define &lt;name&gt; HusqvarnaAutomower</code>
	<br><br>
	Beispiel:
	<ul><br>
		<code>define myMower HusqvarnaAutomower</code><br>
	</ul>
</ul>
<br>
<a name="HusqvarnaAutomowerreadings"></a>
<b>Readings</b>
<ul>
	<li>address - Adresse, welche in der App eingetragen wurde (Langversion)</li>
	<li>authorized_user_ids - </li>
	<li>city - PLZ, Stadt</li>
	<li>devices - Anzahl der Ger&auml;te, welche in der GardenaCloud angemeldet sind (Gateway z&auml;hlt mit)</li>
	<li>lastRequestState - Letzter abgefragter Status der Bridge</li>
	<li>latitude - Breitengrad des Grundst&uuml;cks</li>
	<li>longitude - Längengrad des Grundst&uuml;cks</li>
	<li>name - Name für das Grundst&uuml;ck – Default „My Garden“</li>
	<li>state - Status der Bridge</li>
	<li>token - SessionID</li>
	<li>zones - </li>
</ul>



=end html_DE
