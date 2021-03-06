#!/usr/bin/perl -w
#
# Geocoding utility functions.  Uses Google API.  2-clause BSD license.
#
# Copyright 2018 /u/molo1134. All rights reserved.

package Location;
require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(argToCoords qthToCoords coordToGrid geolocate gridToCoord distBearing coordToTZ decodeEntities);

use utf8;
use Math::Trig;
use Math::Trig 'great_circle_distance';
use Math::Trig 'great_circle_bearing';
use URI::Escape;

sub gridToCoord {
  my $gridstr = shift;

  if (not $gridstr =~ /^[A-R]{2}[0-9]{2}([A-X]{2})?/i ) {
    print "\ninvalid grid\n";
    return undef;
  }

  my @grid = split (//, uc($gridstr));

  if ($#grid < 3) {
    return undef;
  }

  my $lat;
  my $lon;
  my $formatter;

  $lon = ((ord($grid[0]) - ord('A')) * 20) - 180;
  $lat = ((ord($grid[1]) - ord('A')) * 10) - 90;
  $lon += ((ord($grid[2]) - ord('0')) * 2);
  $lat += ((ord($grid[3]) - ord('0')) * 1);

  if ($#grid >= 5) {
    $lon += ((ord($grid[4])) - ord('A')) * (5/60);
    $lat += ((ord($grid[5])) - ord('A')) * (5/120);
    # move to center of subsquare
    $lon += (5/120);
    $lat += (5/240);
    # not too precise
    $formatter = "%.4f";
  } else {
    # move to center of square
    $lon += 1;
    $lat += 0.5;
    # even less precise
    $formatter = "%.1f";
  }

  # not too precise
  $lat = sprintf($formatter, $lat);
  $lon = sprintf($formatter, $lon);

  return join(',', $lat, $lon);
}

sub coordToGrid {
  my $lat = shift;
  my $lon = shift;
  my $grid = "";

  $lon = $lon + 180;
  $lat = $lat + 90;

  $grid .= chr(ord('A') + int($lon / 20));
  $grid .= chr(ord('A') + int($lat / 10));
  $grid .= chr(ord('0') + int(($lon % 20)/2));
  $grid .= chr(ord('0') + int(($lat % 10)/1));
  $grid .= chr(ord('a') + int(($lon - (int($lon/2)*2)) / (5/60)));
  $grid .= chr(ord('a') + int(($lat - (int($lat/1)*1)) / (2.5/60)));

  return $grid;
}

sub qthToCoords {
  my $place = uri_escape_utf8(shift);
  my $lat = undef;
  my $lon = undef;
  my $url = "http://maps.googleapis.com/maps/api/geocode/xml?address=$place&sensor=false";

  my $tries = 0;

  RESTART:
  $tries++;

  open (HTTP, '-|', "curl -k -s '$url'");
  binmode(HTTP, ":utf8");
  GET: while (<HTTP>) {
    #print;
    chomp;
    if (/OVER_QUERY_LIMIT/) {
      #print "warning: over query limit\n";
      close(HTTP);
      print "error: over query limit. please try again.\n" if $tries > 3;
      exit $::exitnonzeroonerror if $tries > 3;
      goto RESTART;
    }
    if (/<lat>([+-]?\d+.\d+)<\/lat>/) {
      $lat = $1;
    }
    if (/<lng>([+-]?\d+.\d+)<\/lng>/) {
      $lon = $1;
    }
    if (defined($lat) and defined($lon)) {
      last GET;
    }
  }
  close HTTP;

  if (defined($lat) and defined($lon)) {
    return "$lat,$lon";
  } else {
    return undef;
  }
}

sub geolocate {
  my $lat = shift;
  my $lon = shift;

  my $url = "http://maps.googleapis.com/maps/api/geocode/xml?latlng=$lat,$lon&sensor=false";

  my $newResult = 0;
  my $getnextaddr = 0;
  my $addr = undef;
  my $type = undef;

  my %results;
  my $tries = 0;

  RESTART:

  open (HTTP, '-|', "curl -k -s '$url'");
  binmode(HTTP, ":utf8");
  while (<HTTP>) {
    #print;
    chomp;

    if (/OVER_QUERY_LIMIT/) {
      #print "warning: over query limit\n" unless defined($raw) and $raw == 1;
      close(HTTP);
      exit $::exitnonzeroonerror if $tries > 3;
      goto RESTART;
    }

    last if /ZERO_RESULTS/;

    if (/<result>/) {
      $newResult = 1;
      next;
    }

    if ($newResult == 1 and /<type>([^<]+)</) {
      $type = $1;
      $getnextaddr = 1;
      $newResult = 0;
      next;
    }

    if ($getnextaddr == 1 and /<formatted_address>([^<]+)</) {
      #print "$type => $1\n";
      $results{$type} = $1;
      $getnextaddr = 0;
      next;
    }
  }
  close HTTP;

  if (defined($results{"neighborhood"})) {
    $addr = $results{"neighborhood"};
  } elsif (defined($results{"locality"})) {
    $addr = $results{"locality"};
  } elsif (defined($results{"administrative_area_level_3"})) {
    $addr = $results{"administrative_area_level_3"};
  } elsif (defined($results{"postal_town"})) {
    $addr = $results{"postal_town"};
  } elsif (defined($results{"political"})) {
    $addr = $results{"political"};
  } elsif (defined($results{"postal_code"})) {
    $addr = $results{"postal_code"};
  } elsif (defined($results{"administrative_area_level_2"})) {
    $addr = $results{"administrative_area_level_2"};
  } elsif (defined($results{"administrative_area_level_1"})) {
    $addr = $results{"administrative_area_level_1"};
  } elsif (defined($results{"country"})) {
    $addr = $results{"country"};
  } elsif (defined($results{"sublocality"})) {
    $addr = $results{"sublocality"};
  } elsif (defined($results{"sublocality_level_3"})) {
    $addr = $results{"sublocality_level_3"};
  } elsif (defined($results{"sublocality_level_4"})) {
    $addr = $results{"sublocality_level_4"};
  }

  return $addr;
}

sub argToCoords {
  my $arg = shift;
  my $type;

  if ($arg =~ /^(grid:)? ?([A-R]{2}[0-9]{2}([a-x]{2})?)/i) {
    $arg = $2;
    $type = "grid";
  } elsif ($arg =~ /^(geo:)? ?([-+]?\d+(.\d+)?,\s?[-+]?\d+(.\d+)?)/i) {
    $arg = $2;
    $type = "geo";
  } else {
    $type = "qth";
  }

  my $lat = undef;
  my $lon = undef;
  my $grid = undef;

  if ($type eq "grid") {
    $grid = $arg;
  } elsif ($type eq "geo") {
    ($lat, $lon) = split(',', $arg);
  } elsif ($type eq "qth") {
    my $ret = qthToCoords($arg);
    if (!defined($ret)) {
      #print "'$arg' not found.\n";
      #exit $::exitnonzeroonerror;
      return undef;
    }
    ($lat, $lon) = split(',', $ret);
  }

  if (defined($grid)) {
    ($lat, $lon) = split(',', gridToCoord(uc($grid)));
  }

  return join(',', $lat, $lon);
}

sub distBearing {
  my $lat1 = shift;
  my $lon1 = shift;
  my $lat2 = shift;
  my $lon2 = shift;

  my @origin = NESW($lon1, $lat1);
  my @foreign = NESW($lon2, $lat2);

  my ($dist, $bearing);

  # disable "experimental" warning on smart match operator use
  no if $] >= 5.018, warnings => "experimental::smartmatch";

  if (@origin ~~ @foreign) {	  # smart match operator - equality comparison
    $dist = 0;
    $bearing = 0;
  } else {
    $dist = great_circle_distance(@origin, @foreign, 6378.1);
    $bearing = rad2deg(great_circle_bearing(@origin, @foreign));
  }

  return ($dist, $bearing);
}

# Notice the 90 - latitude: phi zero is at the North Pole.
# Example: my @London = NESW( -0.5, 51.3); # (51.3N 0.5W)
# Example: my @Tokyo  = NESW(139.8, 35.7); # (35.7N 139.8E)
sub NESW {
  deg2rad($_[0]), deg2rad(90 - $_[1])
}

sub coordToTZ {
  my $lat = shift;
  my $lon = shift;

  my $now = time();
  my $url = "https://maps.googleapis.com/maps/api/timezone/json?location=$lat,$lon&timestamp=$now";

  my ($dstoffset, $rawoffset, $zoneid, $zonename);

  open (HTTP, '-|', "curl -k -s '$url'");
  binmode(HTTP, ":utf8");
  while (<HTTP>) {

    # {
    #    "dstOffset" : 3600,
    #    "rawOffset" : -18000,
    #    "status" : "OK",
    #    "timeZoneId" : "America/New_York",
    #    "timeZoneName" : "Eastern Daylight Time"
    # }

    if (/"(\w+)" : (-?\d+|"[^"]*")/) {
      my ($k, $v) = ($1, $2);
      $v =~ s/^"(.*)"$/$1/;
      #print "$k ==> $v\n";
      if ($k eq "status" and $v ne "OK") {
	return undef;
      }
      $dstOffset = $v if $k eq "dstOffset";
      $rawOffset = $v if $k eq "rawOffset";
      $zoneid = $v if $k eq "timeZoneId";
      $zonename = $v if $k eq "timeZoneName";
    }
  }
  close(HTTP);

  return $zoneid;
}

sub decodeEntities {
  my $s = shift;
  $s =~ s/&#(\d+);/chr($1)/eg;
  $s =~ s/&#x([0-9a-f]+);/chr(hex($1))/egi;

  $s =~ s/&reg;/®/g;
  $s =~ s/&copy;/©/g;
  $s =~ s/&trade;/™/g;
  $s =~ s/&cent;/¢/g;
  $s =~ s/&pound;/£/g;
  $s =~ s/&yen;/¥/g;
  $s =~ s/&euro;/€/g;
  $s =~ s/&laquo;/«/g;
  $s =~ s/&raquo;/»/g;
  $s =~ s/&bull;/•/g;
  $s =~ s/&dagger;/†/g;
  $s =~ s/&deg;/°/g;
  $s =~ s/&permil;/‰/g;
  $s =~ s/&micro;/µ/g;
  $s =~ s/&middot;/·/g;
  $s =~ s/&rsquo;/’/g;
  $s =~ s/&lsquo;/‘/g;
  $s =~ s/&ldquo;/“/g;
  $s =~ s/&rdquo;/”/g;
  $s =~ s/&ndash;/–/g;
  $s =~ s/&mdash;/—/g;

  $s =~ s/&aacute;/á/g;
  $s =~ s/&Aacute;/Á/g;
  $s =~ s/&acirc;/â/g;
  $s =~ s/&Acirc;/Â/g;
  $s =~ s/&aelig;/æ/g;
  $s =~ s/&AElig;/Æ/g;
  $s =~ s/&agrave;/à/g;
  $s =~ s/&Agrave;/À/g;
  $s =~ s/&aring;/å/g;
  $s =~ s/&Aring;/Å/g;
  $s =~ s/&atilde;/ã/g;
  $s =~ s/&Atilde;/Ã/g;
  $s =~ s/&auml;/ä/g;
  $s =~ s/&Auml;/Ä/g;
  $s =~ s/&ccedil;/ç/g;
  $s =~ s/&Ccedil;/Ç/g;
  $s =~ s/&eacute;/é/g;
  $s =~ s/&Eacute;/É/g;
  $s =~ s/&ecirc;/ê/g;
  $s =~ s/&Ecirc;/Ê/g;
  $s =~ s/&egrave;/è/g;
  $s =~ s/&Egrave;/È/g;
  $s =~ s/&eth;/ð/g;
  $s =~ s/&ETH;/Ð/g;
  $s =~ s/&euml;/ë/g;
  $s =~ s/&Euml;/Ë/g;
  $s =~ s/&iacute;/í/g;
  $s =~ s/&Iacute;/Í/g;
  $s =~ s/&icirc;/î/g;
  $s =~ s/&Icirc;/Î/g;
  $s =~ s/&iexcl;/¡/g;
  $s =~ s/&igrave;/ì/g;
  $s =~ s/&Igrave;/Ì/g;
  $s =~ s/&iquest;/¿/g;
  $s =~ s/&iuml;/ï/g;
  $s =~ s/&Iuml;/Ï/g;
  $s =~ s/&ntilde;/ñ/g;
  $s =~ s/&Ntilde;/Ñ/g;
  $s =~ s/&oacute;/ó/g;
  $s =~ s/&Oacute;/Ó/g;
  $s =~ s/&ocirc;/ô/g;
  $s =~ s/&Ocirc;/Ô/g;
  $s =~ s/&oelig;/œ/g;
  $s =~ s/&OElig;/Œ/g;
  $s =~ s/&ograve;/ò/g;
  $s =~ s/&Ograve;/Ò/g;
  $s =~ s/&ordf;/ª/g;
  $s =~ s/&ordm;/º/g;
  $s =~ s/&oslash;/ø/g;
  $s =~ s/&Oslash;/Ø/g;
  $s =~ s/&otilde;/õ/g;
  $s =~ s/&Otilde;/Õ/g;
  $s =~ s/&ouml;/ö/g;
  $s =~ s/&Ouml;/Ö/g;
  $s =~ s/&szlig;/ß/g;
  $s =~ s/&thorn;/þ/g;
  $s =~ s/&THORN;/Þ/g;
  $s =~ s/&uacute;/ú/g;
  $s =~ s/&Uacute;/Ú/g;
  $s =~ s/&ucirc;/û/g;
  $s =~ s/&Ucirc;/Û/g;
  $s =~ s/&ugrave;/ù/g;
  $s =~ s/&Ugrave;/Ù/g;
  $s =~ s/&uml;/ö/g;
  $s =~ s/&uuml;/ü/g;
  $s =~ s/&Uuml;/Ü/g;
  $s =~ s/&yacute;/ý/g;
  $s =~ s/&Yacute;/Ý/g;
  $s =~ s/&yuml;/ÿ/g;

  $s =~ s/&lt;/</g;
  $s =~ s/&gt;/>/g;
  $s =~ s/&quot;/"/g;
  $s =~ s/&apos;/'/g;
  $s =~ s/&nbsp;/ /g;
  $s =~ s/&amp;/\&/g;

  return $s;
}
