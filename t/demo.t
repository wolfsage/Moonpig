#!/usr/bin/env perl
use Test::Routine;
use Test::Routine::Util -all;
use Test::More;

with(
  't::lib::Factory::Ledger',
);

use t::lib::Logger '$Logger';

use Moonpig::Env::Test;

use Moonpig::Events::Handler::Code;

use Data::GUID qw(guid_string);
use List::Util qw(sum);
use Moonpig::Util qw(class days dollars event);

use namespace::autoclean;

has xid => (
  is      => 'ro',
  isa     => 'Str',
  default => sub { 'yoyodyne://account/' . guid_string },
);

has invoices_to_pay => (
  is      => 'ro',
  isa     => 'Int',
  default => 2,
  traits  => [ 'Number' ],
  handles => {
    'dec_invoices_to_pay' => [ sub => 1 ],
  },
);

has ledger => (
  is   => 'rw',
  does => 'Moonpig::Role::Ledger',
);

sub active_consumer {
  my ($self) = @_;

  $self->ledger->active_consumer_for_xid( $self->xid );
}

sub pay_any_open_invoice {
  my ($self) = @_;

  my $ledger = $self->ledger;

  if (
    $self->invoices_to_pay
    and
    grep { ! $_->is_open and ! $_->is_paid } $ledger->invoices
  ) {
    # There are unpaid invoices!
    my $last_rfp = $ledger->last_request_for_payment;

    # 4. pay and apply payment to invoice

    my $total = sum map { $_->total_amount } $last_rfp->invoices;

    $ledger->add_credit(
      class(qw(Credit::Simulated)),
      { amount => $total },
    );

    $ledger->process_credits;

    $self->dec_invoices_to_pay;
    $Logger->('...');
  }
}

sub log_current_bank_balance {
  my ($self) = @_;

  if (my $consumer = $self->active_consumer) {
    $Logger->log([ "CURRENTLY ACTIVE: %s", $consumer->ident ]);

    if (my $bank = $consumer->bank) {
      $Logger->log([
        "%s still has %s in it",
        $consumer->bank->ident,
        $consumer->bank->unapplied_amount,
      ]);
    } else {
      $Logger->log([
        "%s is still without a bank",
        $consumer->ident,
      ]);
    }
  }
}

# The goal of our end to end test is to prove out the following:
#
# 1. create ledger
# 2. create consumer
# 3. charge, finalize, send invoice
# 4. pay and apply payment to invoice
# 5. create and link bank to consumer
# 6. heartbeats, until...
# 7. consumer charges bank
# 8. until low-funds, goto 6
# 9. setup replacement
# 10. funds expire
# 11a. fail over (if replacement funded)
# 11b. cancel account (if replacement unfunded)

sub process_daily_assertions {
  my ($self, $day) = @_;

  if ($day == 370) {
    # by this time, consumer 1 should've failed over to consumer 2
    my @consumers   = $self->ledger->consumers;
    my $active      = $self->active_consumer;
    my ($inactive)  = grep { $_->guid ne $active->guid } @consumers;

    is(@consumers, 2, "by day 370, we have created a second consumer");
    is(
      $active->guid,
      $inactive->replacement->guid,
      "the active one is the replacement for the original one",
    );
  }

  if ($day == 740) {
    # by this time, consumer 2 should've failed over to consumer 3 and expired
    my @consumers   = $self->ledger->consumers;
    my $active      = $self->active_consumer;

    is(@consumers, 3, "by day 740, we have created a third consumer");
    ok( ! $active,    "...and they are all inactive");
  }
}

test "end to end demo" => sub {
  my ($self) = @_;

  Moonpig->env->stop_clock;

  my $ledger = $self->test_ledger;
  $self->ledger( $ledger );

  my $consumer = $ledger->add_consumer(
    class(qw(Consumer::ByTime)),
    {
      cost_amount        => dollars(50),
      cost_period        => days(365),
      charge_frequency   => days(7), # less frequent to make logs simpler
      charge_description => 'yoyodyne service',
      old_age            => days(30),
      charge_path_prefix => 'yoyodyne.basic',
      grace_until        => Moonpig->env->now + days(3),

      xid                => $self->xid,
      make_active        => 1,

      # XXX: I have NFI what to do here, yet. -- rjbs, 2011-01-12
      replacement_mri    => Moonpig::URI->new(
        "moonpig://test/method?method=template_like_this"
      ),
    },
  );

  for my $day (1 .. 760) {
    $self->process_daily_assertions($day);

    $Logger->log([ 'TICK: %s', q{} . Moonpig->env->now ]) if $day % 30 == 0;

    $ledger->handle_event( event('heartbeat') );

    # Just a little more noise, to see how things are going.
    $self->log_current_bank_balance if $day % 30 == 0;

    $self->pay_any_open_invoice;

    Moonpig->env->elapse_time(86400);
  }

  my @consumers = $ledger->consumers;
  is(@consumers, 3, "three consumers created over the lifetime");

  my $active_consumer = $ledger->active_consumer_for_xid( $self->xid );
  is($active_consumer, undef, "...but they're all inactive now");

  $ledger->_collect_spare_change;
};

run_me;
done_testing;
