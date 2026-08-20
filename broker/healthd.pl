#!/usr/bin/perl
# healthd.pl — minimal /health proxy for the Redpanda broker.
#
# WHY: Railway's RAILPACK build-stage probe (and the root railway.json) hits
# the broker's *primary* port with a fixed path (/health). The redpanda image
# (Debian trixie) does NOT ship a /health route on its Admin API (9644) — only
# /v1/status/ready, /v1/brokers, /metrics. So a /health probe against the Admin
# port returns 404 and the build is rejected ("1/1 replicas never became
# healthy").
#
# FIX: dedicate a small shim process to the broker's PRIMARY port (8080). It
# answers ANY path (including /health) with 200 once redpanda's readiness
# endpoint is up, and 503 before that. This satisfies:
#   - RAILPACK's build-stage validation (which probes primary-port /health).
#   - The live runtime service healthcheck (path-agnostic).
#
# Dependency-free: core Perl (IO::Socket::INET) + the curl that already ships
# in the redpanda image, used only to check redpanda's readiness.
#
# Single-connection-at-a-time accept loop is acceptable because Railway probes
# sequentially (one request, waits, retries).

use strict;
use warnings;
use IO::Socket::INET;

my $port       = defined $ENV{HEALTH_PORT}  ? $ENV{HEALTH_PORT}  : 8080;
my $admin_port = defined $ENV{ADMIN_PORT}   ? $ENV{ADMIN_PORT}   : 9644;
my $ready_url  = defined $ENV{READY_URL}
    ? $ENV{READY_URL}
    : "http://127.0.0.1:" . $admin_port . "/v1/status/ready";

my $srv = IO::Socket::INET->new(
    LocalAddr => '0.0.0.0',
    LocalPort => $port,
    Listen    => 100,
    ReuseAddr => 1,
    Proto     => 'tcp',
) or die "healthd: cannot listen on $port: $!\n";

$| = 1;
print "healthd: listening on 0.0.0.0:" . $port . " (proxy -> " . $ready_url . ")\n";

sub probe_ready {
    # curl is present in the redpanda image. -w "%{http_code}" gives the HTTP
    # status; -s -S keeps stderr visible for diagnosis. Max 4s so a hung
    # readiness endpoint cannot wedge the accept loop.
    my $code = `curl -fsS -o /dev/null -w "%{http_code}" --max-time 4 ${\ $ready_url} 2>/dev/null`;
    $code =~ s/\D+//g;
    return ($code eq "200") ? "200" : "503";
}

while (my $c = $srv->accept) {
    eval {
        # Drain the request head (ignore method/path/body — we answer based
        # solely on broker readiness state).
        my $head = '';
        while (defined(my $line = <$c>)) {
            $head .= $line;
            last if $head =~ /\r?\n\s*\r?\n/;
        }
        my $code  = probe_ready();
        my ($st, $body) = $code eq "200"
            ? ("200 OK", "ok")
            : ("503 Service Unavailable", "not ready");
        my $resp  = "HTTP/1.1 $st\r\n"
                 .  "Content-Type: text/plain\r\n"
                 .  "Content-Length: " . length($body) . "\r\n"
                 .  "Connection: close\r\n\r\n"
                 .  $body;
        print {$c} $resp;
    };
    close $c;
}
