# mux

use this to obtain great parallel powers.  also to alleviate the headache that comes with queues and managing workers.

## Mux.new(:callable, :channels)

`:callable` should be something callable.  this is the method you write that is going to do all of your work for you and it should take one argument.  eg. `sub ($elem) { }`

`:channels` this should be the maximum level of parallelization that you'd like.  defaults to `int(max_threads / 1.5)`.  this will warn but not puke if you specify higher than max_threads parallelization and be warned that if you exceed the scheduler you may find your application locked.

## .demux(callable)

this sets what demuxes the return values from your workers should you so need them.

```perl6
my Mux $m .=new(
  :callable(sub (Int() $x) { $x * 2; }),
);

$m.demux(-> $rval {
  #rval will be 2, then 2, then 4, then 6, etc
});

$q.start: 1,1,2,3; #etc;
```

## .error(callable)

this is a `sub ($error) { }` to be called when there is an unhandled error in the worker (if it's not in your sub then please open a ticket).

## .drain(callable)

this is a `sub (Mux:D) { }` called when the work queue is complete.

## .pause

for pausing the queue, you can still feed the muxer but don't put your fingers in its mouth.

## .paused

will let you know if the muxer is paused

## .unpause

let's the hedonistic muxer consume

## .unpaused

lets you know whether you should keep your hands away from the cage

## .block

finally, if you want to block until the muxer is done processing the queue

## .feed(*@ )

you can feed the muxer while its running, this will not reset the queue or alter current processing but it will cause `.drain` to be called later

