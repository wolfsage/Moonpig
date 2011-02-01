
use Moonpig::Env::Test;
use Moonpig::DateTime;
use Test::More;
use Test::Fatal;

my $now = Moonpig::DateTime->now();
my $t = Moonpig->env->now();
cmp_ok(abs($now - $t), '<=', 1, "env->now is now");

my $epoch = Moonpig::DateTime->new(
  year      => 1970,
  month     => 1,
  day       => 1,
  hour      => 0,
  minute    => 0,
  second    => 0,
  time_zone => "UTC",
);

Moonpig->env->stop_clock_at($epoch);
cmp_ok(Moonpig->env->now, '==', $epoch);
cmp_ok(abs($now - Moonpig->env->now), '>', 1, "env->now is no longer now");

Moonpig->env->stop_clock_at($epoch + 30);
cmp_ok(abs($epoch - Moonpig->env->now), '==', 30, "env->now is 30");

Moonpig->env->elapse_time(30);
cmp_ok(abs($epoch - Moonpig->env->now), '==', 60, "env->now is 60");

like(
  (exception { Moonpig->env->elapse_time(-30) })->ident,
  qr/negative time/,
  "can't elapse negative time",
);

done_testing;
