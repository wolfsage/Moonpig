
use strict;
use warnings;

use Carp qw(confess croak);
use Test::Exception;
use Test::More;
use Test::Routine;
use Test::Routine::Util;

use t::lib::TestEnv;
use Moonpig::Util -all;

use Moonpig::Test::Factory qw(build);

sub setup {
  my ($self) = @_;
  my $stuff = build(cons => { template => 'dummy',
                              bank => dollars(100),
                            });

  return @{$stuff}{qw(ledger cons)};
}

# This is to test that when the hold is for more than 50% of the
# remaining funds, we can still convert it to a transfer.  Note that
# creating the transfer first and then deleting the hold won't work
# with the obvious implementation, since that will cause an overdraft.
test "get and commit hold" => sub {
  my ($self) = @_;
  plan tests => 6;
  my ($Ledger, $c) = $self->setup;
  my $amount = int($c->unapplied_amount * 0.75);
  my $x_remaining = $c->unapplied_amount - $amount;
  my $h = $Ledger->create_transfer({
    type => 'hold',
    from => $c,
    to   => $Ledger->current_journal,
    amount => $amount,
  });
  ok($h);
  is($c->unapplied_amount, $x_remaining);
  my $t = $Ledger->accountant->commit_hold($h);
  ok($t);
  is($t->amount, $amount);
  is($t->type, 'transfer');
  is($c->unapplied_amount, $x_remaining);
};

run_me;
done_testing;
