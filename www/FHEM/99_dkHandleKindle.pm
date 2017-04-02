##############################################
## Stand: 14.01.2017
##############################################
# $Id$
package main;

use strict;
use warnings;
use POSIX;
use Time::Local;

sub dkHandleKindle_Initialize($$) {
 	my ($hash) = @_;
}

my @global_debug = ();

#######################################
##
##
## FUNKTIONEN
##
##
#######################################

sub dkGetYahooWeatherIcon($) {
	my ($icon_name) = @_;
	my $weather_icon_name = dkGetReading('Yahoo_Wetter', $icon_name);
	my %yahoo_meteoconsmap = (
		"tornado" ,					"9",
		"tropicalstorm" ,			"&",
		"hurricane" ,				"!",
		"severethunderstorms" ,		"&",
		"thunderstorms" ,			"0",
		"thunderstorm" ,				"0",
		"mixedrainandsnow" ,			"V",
		"mixedrainandsleet" ,		"X",
		"mixedsnowandsleet" ,       "X",
		"freezingdrizzle" ,         "W",
		"drizzle" ,                 "R",
		"freezingrain",             "W",
		"showers" ,                 "Q",
		"chanceofrain",             "Q",
		"snowflurries" ,            "U",
		"lightsnowshowers" ,        "U",
		"blowingsnow" ,             "W",
		"snow" ,                    "W",
		"hail" ,                    "X",
		"sleet" ,                   "X",
		"dust" ,                    "E",
		"foggy" ,                   "F",
		"haze" ,                    "L",
		"smoky" ,                   "M",
		"blustery" ,                "!",
		"windy" ,                   "S",
		"cold" ,                    "G",
		"cloudy" ,                  "5",
		"mostlycloudy" ,            "N",
		"mostlycloudynight", 		"N",
		"partlycloudy" ,            "H",
		"clear" ,                   "B",
		"sunny" ,                   "B",
		"mostlysunny", 				"B",
		"fair" ,                    "B",
		"mixedrainandhail" ,        "X",
		"hot" ,                     "B",
		"isolatedthunderstorms" ,   "Z",
		"scatteredthunderstorms" ,  "Z",
		"scatteredshowers" ,        "Q",
		"heavysnow" ,               "#",
		"scatteredsnowshowers" ,    "V",
		"thundershowers" ,          "8",
		"snowshowers" ,             "\$",
		"isolatedthundershowers" ,  "R"
    );
	#$weather_icon_name =~ s/_| //g;
	$weather_icon_name =~ s/(_|,| )//g;
	return $yahoo_meteoconsmap{$weather_icon_name};
}

# PROPLANTA (most likely incomplete)
sub dkGetProplantaWeatherIcon($) {
	my ($icon_name) = @_;
	my $weather_icon_name = dkGetReading('proplanta', $icon_name);
	my %proplanta_meteoconsmap = (
        "heiter",                       "H",
        "wolkig",                       "N",
        "Regenschauer",                 "Q",
        "starkbewoelkt",                "Y",
        "Regen",                        "R",
        "bedeckt",                      "N",
        "sonnig",                       "B",
        "Schnee",                       "U",
        "Schneefall",                   "U",
        "Schneeregen",                  "V",
        "Schneeschauer",                "\$",
        "unterschiedlichbewoelktvereinzeltSchauerundGewitter", "Q",
        "Nebel",                        "F",
        "klar",                         "B",
        "Spruehregen",                  "R",
        "keineDaten", 					"H"
	);
	#$weather_icon_name =~ s/_| //g;
	$weather_icon_name =~ s/(_|,| )//g;
	return $proplanta_meteoconsmap{$weather_icon_name};
}

sub dkKindleDashboard() {
	
	my $filename_template = './www/images/template.svg';
	my $filename_output_svg = './www/images/status.svg';    
	my $filename_output_png = './www/images/status.png';    
	
	my $filedata;
	open (DATEI,'<',$filename_template) or die $!;
    while(<DATEI>){
    	$filedata = $filedata.$_;
    }
	close (DATEI);
	
	# MÜLLTERMINE
	my $muell_bio = dkGetReading('data_muelltermine', 'BioTonne');
	my $muell_blau = dkGetReading('data_muelltermine', 'BlaueTonne');
	my $muell_gelb = dkGetReading('data_muelltermine', 'GelbeTonne');
	my $muell_rest = dkGetReading('data_muelltermine', 'Restmuell');
	
	my $muell_next_days = 100;
	my $muell_next_name = "";
	my $muell_heute_name = "";
	
	if ($muell_bio < $muell_next_days && $muell_bio > 0) { $muell_next_days = $muell_bio; $muell_next_name = "Bio-Abfall"; } 
	if ($muell_blau < $muell_next_days && $muell_blau > 0) { $muell_next_days = $muell_blau; $muell_next_name = "Altpapier"; } 
	if ($muell_gelb < $muell_next_days && $muell_gelb > 0) { $muell_next_days = $muell_gelb; $muell_next_name = "Gelber Sack";  } 
	if ($muell_rest < $muell_next_days && $muell_rest > 0) { $muell_next_days = $muell_rest; $muell_next_name = "Restmüll";  } 
	
	if ($muell_next_days > 0 && $muell_next_days != 100) {
		if ($muell_next_days == 1) {
			$muell_next_name = 'Morgen <tspan style="font-weight:bold">' . $muell_next_name . '</tspan>';		
		} else {
			$muell_next_name = $muell_next_name . " / " . $muell_next_days . " Tage";	
		}
	}
	
	if ($muell_bio == 0) { $muell_heute_name = "Bio-Abfall"; } 
	if ($muell_blau == 0) { $muell_heute_name = "Altpapier"; } 
	if ($muell_gelb == 0) { $muell_heute_name = "Gelber Sack";  } 
	if ($muell_rest == 0) { $muell_heute_name = "Restmüll";  } 
	
	$filedata =~ s/MUELLNEXT/$muell_next_name/;		
	$filedata =~ s/MUELLHEUTE/$muell_heute_name/;		

	
	# WETTER
	my $weather_icon_code = dkGetProplantaWeatherIcon('weather');
	#dkDebugAdd($weather_icon_code);

	$filedata =~ s/ICON1/$weather_icon_code/;

	my $weather_icon_2_code = dkGetProplantaWeatherIcon('fc1_weatherDay');
	$filedata =~ s/ICON2/$weather_icon_2_code/;

	my $weather_icon_3_code = dkGetProplantaWeatherIcon('fc2_weatherDay');
	$filedata =~ s/ICON3/$weather_icon_3_code/;

	my $weather_temperature_today = dkGetReading('proplanta', 'temperature');
	$filedata =~ s/TEMP/$weather_temperature_today/;

	my $weather_temperature_today_min = dkGetReading('proplanta', 'fc0_tempMin');
	$filedata =~ s/TMIN1/$weather_temperature_today_min/;

	my $weather_temperature_today_max = dkGetReading('proplanta', 'fc0_tempMax');
	$filedata =~ s/TMAX1/$weather_temperature_today_max/;

	my $weather_temperature_2_min = dkGetReading('proplanta', 'fc1_tempMin');
	$filedata =~ s/TMIN2/$weather_temperature_2_min/;

	my $weather_temperature_2_max = dkGetReading('proplanta', 'fc1_tempMax');
	$filedata =~ s/TMAX2/$weather_temperature_2_max/;

	my $weather_temperature_3_min = dkGetReading('proplanta', 'fc2_tempMin');
	$filedata =~ s/TMIN3/$weather_temperature_3_min/;

	my $weather_temperature_3_max = dkGetReading('proplanta', 'fc2_tempMax');
	$filedata =~ s/TMAX3/$weather_temperature_3_max/;


	# UHRZEIT
	my $now = strftime("\%Y-\%m-\%d \%H:\%M:\%S", localtime);
	$filedata =~ s/UHR/$now/;
	
	# POOL
	my $pool_temperature = dkGetReading('AB_Pool_Sensor_Wassertemperatur', 'temperature');
	$filedata =~ s/POOL/$pool_temperature/;

	# SPEICHERN
	open (DATEI,'>',$filename_output_svg) or die $!;
    print DATEI "$filedata";
	close (DATEI);
	
	system("convert $filename_output_svg -type GrayScale -depth 8 $filename_output_png &");
		
}




#######################################
##
##
## INTERNE FUNKTIONEN
##
##
#######################################


1;