##########################
# bulkCleanup.pl
##########################
use utf8;

my $opts;

$opts->{connection_config} = "$[connection_config]";
$opts->{labmanager_org} = q{$[labmanager_org]};
$opts->{labmanager_work} = q{$[labmanager_work]};
$opts->{labmanager_days_old} = q{$[labmanager_days_old]};
$opts->{labmanager_delete} = q{$[labmanager_delete]};
$opts->{labmanager_name_pattern} = q{$[labmanager_name_pattern]};

$[/myProject/procedure_helpers/preamble]

$gt->bulkCleanup();
exit($opts->{exitcode});