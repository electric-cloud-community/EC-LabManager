##########################
# configurationChangeOwner.pl
##########################
use utf8;

my $opts;

$opts->{connection_config} = "$[connection_config]";
$opts->{labmanager_org} = q{$[labmanager_org]};
$opts->{labmanager_work} = q{$[labmanager_work]};
$opts->{labmanager_configurationid} = q{$[labmanager_configurationid]};
$opts->{labmanager_newownerid} = q{$[labmanager_newownerid]};

$[/myProject/procedure_helpers/preamble]

$gt->configurationChangeOwner();
exit($opts->{exitcode});