
use Mux;
use Test;

plan 9;

my @expected   = 1,10,2,1,10,4,2,1;
my $errored    = 2;
my $sleep-recv = 0;
my $sleeping   = False;

my $q = Mux.new(
  :callable(sub (Int() $want) {
    die "should die zero" if $want == 0;
    is $want, @expected.shift, "correct emission";
    sleep $want;
    $want * 2;
  }),
  :channels(2)
);

$q.demux(-> $data {
  $sleep-recv++ if $sleeping;
});

$q.error(-> $err {
  $errored++;
});

my $drain = $q.start: 1, 0, 10, 2, 1, 0;

sleep 2;

$q.feed: 10, 4, 2, 1;

$q.pause for 1..500;
$sleeping = True;
sleep 30;
$sleeping = False;
$q.unpause for 1..500;

ok $sleep-recv <= 2, "should not receive more values than channels during sleeping";

$q.block;

# vim:syntax=perl6
