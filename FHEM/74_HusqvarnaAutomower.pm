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

# Declare functions
sub HusqvarnaAutomower_Initialize($);
sub HusqvarnaAutomower_Define($$);

sub HusqvarnaAutomower_Notify($$);

sub HusqvarnaAutomower_Attr(@);
sub HusqvarnaAutomower_Set($@);

sub HusqvarnaAutomower_WriteReadings($$);
sub HusqvarnaAutomower_Parse($$);

sub HusqvarnaAutomower_Undef($$);

sub HusqvarnaAutomower_CONNECTED($@);

#----

sub HusqvarnaAutomower_Initialize($) {
	my ($hash) = @_;
	
    $hash->{SetFn}      = "HusqvarnaAutomower_Set";
    $hash->{DefFn}      = "HusqvarnaAutomower_Define";
    $hash->{UndefFn}    = "HusqvarnaAutomower_Undef";
    $hash->{ParseFn}    = "HusqvarnaAutomower_Parse";
    $hash->{NotifyFn} 	= "HusqvarnaAutomower_Notify";
    $hash->{AttrFn}     = "HusqvarnaAutomower_Attr";
    $hash->{AttrList}   = "username " .
                          "password " .
                          "mower " .
                          $readingFnAttributes;

    foreach my $d(sort keys %{$modules{HusqvarnaAutomower}{defptr}}) {
        my $hash = $modules{HusqvarnaAutomower}{defptr}{$d};
        $hash->{VERSION} = $version;
    }

}


sub HusqvarnaAutomower_Define($$){
    my ( $hash, $def ) = @_;
    my @a = split( "[ \t]+", $def );

    return "too few parameters: define <NAME> HusqvarnaAutomower" if( @a < 1 ) ;
    return "Cannot define HusqvarnaAutomower device. Perl modul $missingModul is missing." if ( $missingModul );

    my $name = $a[0];
    %$hash = (%$hash,
        NOTIFYDEV => 'global',
        HusqvarnaAutomower     => { 
            CONNECTED   => 0,
            version     => $version,
            token		=> '',
            provider		=> '',
            user_id		=> '',
            device_id	=> '',
        },
    );

	HusqvarnaAutomower_CONNECTED($hash,'disconnected');

    Log3 $name, 5, "$name: Defined with url:AUTHURL, version:$hash->{HusqvarnaAutomower}->{version}";

	return undef;

}


sub HusqvarnaAutomower_Notify($$) {
    
    my ($hash,$dev) = @_;
    my ($name) = ($hash->{NAME});

    Log3 $name, 5, "NOTIFY STARTED";
 	
    return if($dev->{NAME} ne "global");
    return if(!grep(m/^DEFINED|MODIFIED|INITIALIZED|REREADCFG$/, @{$dev->{CHANGED}}));

    if(AttrVal($name, "disable", 0)) {
        Log3 $name, 5, "Device '$name' is disabled, do nothing...";
        HusqvarnaAutomower_CONNECTED($hash,'disabled');
    } else {
        HusqvarnaAutomower_CONNECTED($hash,'initialized');
        HusqvarnaAutomower_DoUpdate($hash);
        
    }
    return undef;
}


sub HusqvarnaAutomower_DoUpdate($) {
    my ($hash) = @_;
    my ($name) = $hash->{NAME};
    
    Log3 $name, 5, "$name UPDATE - executed.";

    if (HusqvarnaAutomower_CONNECTED($hash) eq "disabled") {
        Log3 $name, 5, "$name - Device is disabled.";
        return undef;
    }

	if (HusqvarnaAutomower_CONNECTED($hash)) {
		Log3 $name, 5, "READY FOR UPDATE";
        HusqvarnaAutomower_getMower($hash);

        # do stuff
		# get status of automower        
        
        # trigger next update
        # Unifi_NextUpdateFn($hash,$self);

	} else {
		HusqvarnaAutomower_CONNECTED($hash,'disconnected');
        HusqvarnaAutomower_APIAuth($hash);
	}

}


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
	my $number = 0;
	if ($attr{$name}{mower}) { 
		$number = $attr{$name}{mower};
	}

    if($err ne "") {
        Log3 $name, 5, "error while requesting ".$param->{url}." - $err";     
                                           
    } elsif($data ne "") {
	    
		if ($data eq "[]") {
		    	Log3 $name, 3, "Please register an automower first";
			
		} else {
		    	Log3 $name, 3, "Automower(s) found"; 			
			Log3 $name, 3, $data; 
			#my $result = decode_json($data);
		    #if ($result->{errors}) {
			#    Log3 $name, 3, "Error: " . $result->{errors}[0]->{detail};
		    #} else {
		    #    Log3 $name, 3, "$data"; 
		    #}
		}
	    
	}	
	
	return undef;
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

sub HusqvarnaAutomower_Attr(@) {
    my ( $cmd, $name, $attrName, $attrVal ) = @_;
    my $hash = $defs{$name};
	Log3 $name, 5, "ATTR";
    if($cmd eq "set") {
		Log3 $name, 5, "ATTR SET";
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


sub HusqvarnaAutomower_Set($@){}


sub HusqvarnaAutomower_WriteReadings($$){}
sub HusqvarnaAutomower_Parse($$){}




sub HusqvarnaAutomower_APIAuth($) {
    my ($hash, $def) = @_;
    my $name = $hash->{NAME};
    my $username = $attr{$name}{username};
    my $password = $attr{$name}{password};
    
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
        header     	=> "Content-Type: application/json\r\nAccept: application/json",  
		data 		=> $json,
        callback   	=> \&HusqvarnaAutomower_APIAuthResponse,
    });  
    
    return undef;                                                                                   
}

sub HusqvarnaAutomower_APIAuthResponse($) {
    my ($param, $err, $data) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};

    if($err ne "") {
        Log3 $name, 5, "error while requesting ".$param->{url}." - $err";     
                                           
    } elsif($data ne "") {
	    
	    my $result = decode_json($data);
	    if ($result->{errors}) {
		    Log3 $name, 5, "Error: " . $result->{errors}[0]->{detail};
	    } else {
	        Log3 $name, 5, "$data"; 

			$hash->{HusqvarnaAutomower}->{token} = $result->{data}{id};
			$hash->{HusqvarnaAutomower}->{provider} = $result->{data}{attributes}{provider};
			$hash->{HusqvarnaAutomower}->{user_id} = $result->{data}{attributes}{user_id};

			# getMower device_id
			$hash->{HusqvarnaAutomower}->{device_id} = "";

			# set Readings			
			readingsSingleUpdate($hash,'token',$result->{data}{id},1);
			readingsSingleUpdate($hash,'provider',$result->{data}{attributes}{provider},1);
			readingsSingleUpdate($hash,'user_id',$result->{data}{attributes}{user_id},1);
			readingsSingleUpdate($hash,'device_id',"",1);
			
			HusqvarnaAutomower_CONNECTED($hash,'connected');
			HusqvarnaAutomower_DoUpdate($hash);
			return undef;                                                                                   

	    }
        
    }
    
    return undef;                                                                                   

}



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
