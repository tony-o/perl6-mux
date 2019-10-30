
use Mux;
use Test;

plan 6;

my @expected = 1, 1, 1;
my $fed = False;

my $q = Mux.new(
  :callable(sub (Int() $want) {
    $want;
  }),
  :channels(2)
);

$q.demux(-> $data {
  my $l = @expected.shift;
  is $data, $l, "correct emission (got: $data, expected: $l)";
});

$q.drain(-> $worker {
  if !$fed {
    is @expected.elems, 1, "should have one more expecting in drain";
    $fed = True;
    $worker.feed: 1;
  } else {
    is @expected.elems, 0, 'should have no more expecting in drain';
  }
});

$q.start: 1, 1;

$q.block;

ok @expected.elems == 0, "should not be expecting anything else at end";

# vim:syntax=perl6
