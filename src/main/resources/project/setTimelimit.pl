##########################
# setTimelimit.pl
##########################
use strict;
use warnings;
use ElectricCommander;

use constant {
	FALSE  => 0,
	TRUE   => 1,
	
	DEFAULT_TIMEOUT => '',
	DEFAULT_TIMEOUT_LOCATION => '/myCall/labmanager_timelimit',
};

my $timelimit = "$[labmanager_timeout]";

if (!defined($timelimit) or !isNumber($timelimit) or $timelimit <= 0) {
	$timelimit = DEFAULT_TIMEOUT;
}

my $ec = new ElectricCommander();
$ec->abortOnError(0);
my $setResult = $ec->setProperty(DEFAULT_TIMEOUT_LOCATION, $timelimit);

if ($setResult eq '') {
	print "An error occured when setting timeout to step\n";
} else {
	if ($timelimit eq '') {
		print "No timeout set\n";
	} else {
		print "Timeout set to $timelimit minute(s)\n";
	}
}

###############################
# isNumber - Determine if a variable is a number or not
#
# Arguments:
#   var
#
# Returns:
#   1 if true, 0 false
#
################################
sub isNumber {
	my ($var) = @_;
	if ($var =~ /^[+-]?\d+$/ ) {
    	return TRUE;
	} else {
	    return FALSE;
	}	
}
