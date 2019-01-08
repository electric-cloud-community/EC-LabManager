##########################
# deploy.pl
##########################
use utf8;

my $opts;

$opts->{connection_config} = "$[connection_config]";
$opts->{labmanager_org} = q{$[labmanager_org]};
$opts->{labmanager_work} = q{$[labmanager_work]};
$opts->{labmanager_config} = q{$[labmanager_config]};
$opts->{labmanager_fencedmode} = q{$[labmanager_fencedmode]};
$opts->{labmanager_physical_network} = q{$[labmanager_physical_network]};

# Specify minimum Lab Manager version
$opts->{labmanager_version} = "";

$[/myProject/procedure_helpers/preamble]

$gt->deploy();
exit($opts->{exitcode});