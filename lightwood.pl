#!/usr/bin/perl -wT

use strict;
use Lightwood;

#END { unlink("lightwood.pid") }

# Create a new instance
my $lightwood = Lightwood->new();

# Load the config file
if (scalar @ARGV < 1) {
  die "No config file specified"
}
$lightwood->parseconfig($ARGV[0]);

# Write a PID file
open my $pidfile, ">lightwood.pid";
print $pidfile $$;
print STDERR "pid=$$\n";
close $pidfile;

# Start!
$lightwood->start();
