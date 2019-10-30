my @open;

END {
  for @open -> $mux { $mux.block; }
};

class Mux {
  has @!queue;
  has $!callable;
  has %!channels;
  has $!channels;
  has $!demux;
  has $!demux-error;
  has $!demux-drain;
  has $!pause;
  has $!controller;
  has $!fed;
  has $!closing;

  submethod BUILD(Callable() :$!callable, :@!queue = [], Int :$!channels = ($*SCHEDULER.max_threads / 1.5).Int) {
    warn 'Asking for more channels than provided by scheduler (asked for: ' ~ $!channels ~ ')'
      if $!channels+1 > $*SCHEDULER.max_threads;

    $!demux       = Supplier.new;
    $!demux-error = Supplier.new;
    $!demux-drain = Supplier.new;
    $!fed         = Promise.new;
    $!closing     = False;
    $!controller  = start {
      while !$!closing {
        await $!fed;
        $!fed = Promise.new;
        while @!queue.elems {
          CATCH { default { .say; } }
          self!build-channels;
          my $elem  = @!queue.shift;
          my $queue = %!channels.keys.grep({ %!channels{$_}<open> == 1 }).first;
          if !$queue {
            # need to await
            await |Promise.anyof( %!channels.keys.map({ %!channels{$_}<promise> }).grep({ .defined && $_ ~~ Promise }) );
            $queue = %!channels.keys.grep({ %!channels{$_}<open> == 1 }).first;
          }
          await $!pause if $!pause ~~ Promise && $!pause.status ~~ Planned;
          %!channels{$queue}<open> = 0;
          %!channels{$queue}<promise> = Promise.new if %!channels{$queue}<promise>.status !~~ Planned;
          %!channels{$queue}<channel>.send($elem);
        }
        $!demux-drain.emit: self;
        %!channels.keys.map({try %!channels{$_}<channel>.close;});
        %!channels = ();
      }
    };
  }

  submethod DESTROY {
    $!closing = True;
    await $!controller;
  }

  submethod TWEAK(|) {
    @open.push: self;
    self.start if @!queue.elems;
  }

  method force-close {
    $!closing = True;
    try $!fed.keep;
  }

  method close {
    $!closing = True;
    try $!fed.keep if @!queue.elems == 0;
  }

  method !build-channels {
    for 1 .. min(@!queue.elems, $!channels) -> $x is copy {
      next if %!channels{"worker$x"}:exists && !%!channels{"worker$x"}<channel>.closed;
      %!channels{"worker$x"} = %(
        id      => "worker$x",
        channel => Channel.new,
        promise => Promise.new,
        open    => 1,
      );
      %!channels{"worker$x"}<thread> = start {
        react { whenever %!channels{"worker$x"}<channel> {
          CATCH {
            default {
              $!demux-error.emit: $_;
              %!channels{"worker$x"}<open> = 1;
              try %!channels{"worker$x"}<promise>.break;
            }
          };
          my $elem = $_;
          $!demux.emit: $!callable($elem);
          %!channels{"worker$x"}<open> = 1;
          %!channels{"worker$x"}<promise>.keep;
        } }
      };
    }
  }

  method feed(*@data) {
    unless $!closing {
      @!queue.push: |@data;
      self.start;
    }
  }

  method pause {
    return if $!pause ~~ Promise && $!pause.status ~~ Planned;
    $!pause = Promise.new;
  }

  method paused (--> Bool) { $!pause ~~ Promise && $!pause.status ~~ Planned; }

  method unpause {
    try $!pause.keep;
  }

  method unpaused (--> Bool) { not self.paused; }

  method start(*@queue) {
    CATCH { default { .say; } }
    @!queue.push(|@queue);
    try $!fed.keep;
  }

  method demux(Callable() $callable) {
    $!demux.Supply.tap: $callable;
  }

  method error(Callable() $callable) {
    $!demux-error.Supply.tap: $callable;
  }

  method drain(Callable() $callable) {
    $!demux-drain.Supply.tap: $callable;
  }

  method channels(--> Int) { $!channels; }

  method block {
    await $!controller;
  }
}
