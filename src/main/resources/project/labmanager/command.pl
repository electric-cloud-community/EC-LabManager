##########################
# command.pl
##########################
use utf8;

my $opts;

$opts->{connection_config} = "$[connection_config]";
$opts->{labmanager_org} = q{$[labmanager_org]};
$opts->{labmanager_work} = q{$[labmanager_work]};
$opts->{labmanager_cmd} = q{$[labmanager_cmd]};
$opts->{labmanager_cmdargs} = q{$[labmanager_cmdargs]};

$[/myProject/procedure_helpers/preamble]

$gt->command();
exit($opts->{exitcode});