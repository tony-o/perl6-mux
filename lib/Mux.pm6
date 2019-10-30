class Mux {
  has @!queue;
  has $!callable;
  has %!channels;
  has $!channels;
  has $!demux;
  has $!demux-error;
  has $!demux-drain;
  has $!pause;
  has @!controller;
  has $!controller-loop;

  submethod BUILD(Callable() :$!callable, :@!queue = [], Int :$!channels = ($*SCHEDULER.max_threads / 1.5).Int) {
    warn 'Asking for more channels than provided by scheduler (asked for: ' ~ $!channels ~ ')'
      if $!channels+1 > $*SCHEDULER.max_threads;

    $!demux       = Supplier.new;
    $!demux-error = Supplier.new;
    $!demux-drain = Supplier.new;
  }

  submethod TWEAK(|) {
    self.start if @!queue.elems;
  }

  method feed(*@data) {
    @!queue.push: |@data;
    self.start;
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
    return if $!controller-loop ~~ Promise && $!controller-loop.status ~~ Planned;
    await Promise.allof(|@!controller);
    @!controller.push: start { #controller
      $!controller-loop = Promise.new;
      #build channels
      for 1 .. min(@!queue.elems, $!channels) -> $x is copy {
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
      while @!queue.elems {
        my $elem = @!queue.shift;
        CATCH { default { } };
        my $queue = %!channels.keys.grep({ %!channels{$_}<open> == 1 }).first;
        if !$queue {
          # need to await
          await |Promise.anyof( %!channels.keys.map({ %!channels{$_}<promise> }) );
          $queue = %!channels.keys.grep({ %!channels{$_}<open> == 1 }).first;
        }
        await $!pause if $!pause ~~ Promise && $!pause.status ~~ Planned;
        %!channels{$queue}<open> = 0;
        %!channels{$queue}<promise> = Promise.new if %!channels{$queue}<promise>.status !~~ Planned;
        %!channels{$queue}<channel>.send($elem);
      }
      $!controller-loop.keep;

      await |Promise.allof(%!channels.keys.map({ %!channels{$_}<promise> }) );

      for %!channels.keys { %!channels{$_}<channel>.close; }
      %!channels = ();
      start { $!demux-drain.emit: self; }
    };
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
    while @!controller.elems {
      await @!controller.shift;
    }
  }
}
