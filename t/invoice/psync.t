use Test::Routine;
use Test::More;
use Test::Routine::Util;
use Test::Fatal;

use t::lib::TestEnv;
use Stick::Util qw(ppack);

use Moonpig::Util qw(class days dollars event weeks years);

with(
  't::lib::Factory::EventHandler',
  'Moonpig::Test::Role::LedgerTester',
);

use t::lib::ConsumerTemplateSet::Demo;
use Moonpig::Test::Factory qw(do_with_fresh_ledger);

my $jan1 = Moonpig::DateTime->new( year => 2000, month => 1, day => 1 );

before run_test => sub {
  Moonpig->env->email_sender->clear_deliveries;
  Moonpig->env->stop_clock_at($jan1);
};

sub do_test (&) {
  my ($code) = @_;
  do_with_fresh_ledger({ c => { class => class("t::Consumer::VaryingCharge"),
                                total_charge_amount => dollars(7),
                                cost_period => days(7),
                                replacement_plan => [ get => '/nothing' ],
                              }}, sub {
    my ($ledger) = @_;
    my $c = $ledger->get_component("c");
    my ($credit) = $ledger->add_credit(
      class(qw(Credit::Simulated)),
      { amount => dollars(7) },
    );
    $ledger->name_component("credit", $credit);

    $code->($ledger, $c);
  });
}

sub elapse {
  my ($ledger) = @_;
  Moonpig->env->elapse_time(86_400);
  $ledger->heartbeat;
}

test 'setup sanity checks' => sub {
  do_test {
    my ($ledger, $c) = @_;
    ok($c);
    ok($c->does('Moonpig::Role::Consumer::ByTime'));
    ok($c->does("t::lib::Role::Consumer::VaryingCharge"));
    is($c->_predicted_shortfall, 0, "initially no predicted shortfall");
    is($c->expected_funds({ include_unpaid_charges => 1 }), dollars(7),
       "expected funds incl unpaid");
    is($c->expected_funds({ include_unpaid_charges => 0 }), 0, "expected funds not incl unpaid");
    is($c->_estimated_remaining_funded_lifetime({ amount => dollars(7) }), days(7),
      "est lifetime 7d");

    elapse($ledger);

    is($c->expected_funds({ include_unpaid_charges => 1 }), dollars(7),
       "expected funds incl unpaid");
    is($c->expected_funds({ include_unpaid_charges => 0 }), dollars(7),
       "expected funds not incl unpaid");
    is($c->unapplied_amount, dollars(7), "did not spend any money yet");
    is($c->_predicted_shortfall, 0, "initially no predicted shortfall");

    my @inv = $ledger->invoices;
    is(@inv, 1, "one invoice");
    ok($inv[0]->is_closed, "the invoice is closed");
    ok($inv[0]->is_paid, "the invoice is paid");

    my @qu = $ledger->quotes;
    is(@qu, 0, "no quotes");

  };
};

test 'quote' => sub {
  do_test {
    my ($ledger, $c) = @_;
    my $sender = Moonpig->env->email_sender;

    is($c->_predicted_shortfall, 0, "initially no predicted shortfall");
    elapse($ledger);
    is(scalar($ledger->quotes), 0, "no quotes yet");
    elapse($ledger);
    is(scalar($ledger->quotes), 0, "no quotes yet");

    Moonpig->env->process_email_queue;
    is(() = $sender->deliveries, 1, "one email delivery (the invoice)");
    Moonpig->env->email_sender->clear_deliveries;

    $c->total_charge_amount(dollars(14));
    is($c->_predicted_shortfall, weeks(1/2), "double charge -> shortfall 1/2 week");
    elapse($ledger);
    is(my ($qu) = $ledger->quotes, 1, "psync quote sent");
    ok($qu->is_closed, "quote is closed");
    is (my ($ch) = $qu->all_charges, 1, "one charge on psync quote");
    ok($ch->has_tag("moonpig.psync"), "charge is properly tagged");
    is($ch->owner_guid, $c->guid, "charge owner");
    is($ch->amount, dollars(7), "charge amount");

    Moonpig->env->process_email_queue;
    my $sender = Moonpig->env->email_sender;
    is(my ($delivery) = $sender->deliveries, 1, "one email delivery (the psync quote)");
  };
};

test 'regression' => sub {
  my ($self) = @_;

  do_with_fresh_ledger({ c => { template => 'demo-service',
				minimum_chain_duration => years(6),
			      }}, sub {
    my ($ledger) = @_;

    my $invoice = $ledger->current_invoice;
    $ledger->name_component("initial invoice", $invoice);
    $ledger->heartbeat;

    my $n_invoices = () = $ledger->invoices;
    note "$n_invoices invoice(s)";
    my @quotes = $ledger->quotes;
    note @quotes + 0, " quote(s)";

#    require Data::Dumper;
#    print Data::Dumper::Dumper(ppack($invoice)), "\n";;

    pass();
  });

};

run_me;
done_testing;
