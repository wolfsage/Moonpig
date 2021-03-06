
use strict;
use warnings;

use Carp qw(confess croak);
use Moonpig::Util -all;
use Test::Routine;
use Test::More;
use Test::Routine::Util;

use t::lib::TestEnv;
use Moonpig::Test::Factory qw(build_ledger);

test basic => sub {
  my ($self) = @_;
  my $ledger = build_ledger();
  ok($ledger->accountant, "default ledger has accountant");
  isa_ok($ledger->accountant, "Moonpig::Ledger::Accountant",
         "It is in the right class");
};

run_me;
done_testing;
