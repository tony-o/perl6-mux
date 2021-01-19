
use Mux;
use Test;

plan 7;

my @expected = 1, 1, 1;
my $fed = False;
my $done = Promise.new;

my $q = Mux.new(
  :callable(sub (Int() $want) {
    $want;
  }),
  :channels(2)
);

$q.demux(-> $data {
  my $l = @expected.shift;
  say "==> DEMUX $data";
  is $data, $l, "correct emission (got: $data, expected: $l)";
});

$q.drain(-> $worker {
  sleep 1; # queue drains too fast and causes flapping
  if !$fed {
    say "==> drain !fed";
    is @expected.elems, 1, "should have one more expecting in drain";
    $fed = True;
    $worker.feed: 1;
  } else {
    say "==> drain fed";
    is @expected.elems, 0, 'should have no more expecting in drain';
    try $done.keep; # Test doesn't wait for END
  }
});

$q.start: 1, 1;

await $done;
$q.close;
$q.block;
say "==> blocked";
ok @expected.elems == 0, "should not be expecting anything else at end";

# vim:syntax=perl6
