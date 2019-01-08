##########################
# snapshot.pl
##########################
use utf8;

my $opts;

$opts->{connection_config} = "$[connection_config]";
$opts->{labmanager_org}    = q{$[labmanager_org]};
$opts->{labmanager_work}   = q{$[labmanager_work]};
$opts->{Tag}               = q{$[tag]};
$opts->{results}           = q{$[results]};
$opts->{labmanager_config} = q{$[labmanager_config]};

$[/myProject/procedure_helpers/preamble]

$gt->snapshot();
exit($opts->{exitcode});
