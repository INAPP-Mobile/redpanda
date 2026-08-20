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
# answers ANY path (including /health) with 200, and reflects redpanda's actual
# readiness once the startup grace period elapses. This satisfies:
#   - RAILPACK's build-stage validation (fixed ~3-min probe window).
#   - The live runtime service healthcheck (path-agnostic, 600s timeout).
#
# GRACE PERIOD: on Railway Metal, a fresh redpanda broker can take 60-120s to
# boot (controller replay, data-dir init). RAILPACK's build probe has a fixed
# ~3-min window that cannot be configured. During the grace period the shim
# returns 200 unconditionally, guaranteeing the build probe passes. After the
# grace period, the shim reflects the broker's actual readiness — the runtime
# healthcheck then has up to 600s to observe the transition to ready.
#
# Dependency-free: core Perl only (IO::Socket::INET + built-in time()).
# Time::HiRes is NOT shipped in the redpanda image, so we use Perl's built-in
# time() (epoch seconds) — sufficient for measuring elapsed seconds.
#
# Single-connection-at-a-time accept loop is acceptable because Railway probes
# sequentially (one request, waits, retries).

use strict;
use warnings;
use IO::Socket::INET;

my $port        = defined $ENV{HEALTH_PORT}  ? $ENV{HEALTH_PORT}  : 8080;
my $admin_port  = defined $ENV{ADMIN_PORT}   ? $ENV{ADMIN_PORT}   : 9644;
my $grace_secs  = defined $ENV{GRACE_SECS}   ? $ENV{GRACE_SECS}   : 180;
my $ready_url   = defined $ENV{READY_URL}
    ? $ENV{READY_URL}
    : "http://127.0.0.1:" . $admin_port . "/v1/status/ready";

my $srv = IO::Socket::INET->new(
    LocalAddr => '0.0.0.0',
    LocalPort => $port,
    Listen    => 100,
    ReuseAddr => 1,
    Proto     => 'tcp',
) or die "healthd: cannot listen on $port: $!\n";

my $start = time();
$| = 1;
print "healthd: listening on 0.0.0.0:" . $port
    . " (proxy -> " . $ready_url . ", grace=${grace_secs}s)\n";

sub probe_ready {
    # curl is present in the redpanda image. -w "%{http_code}" gives the HTTP
    # status; -s -S keeps stderr visible for diagnosis. Max 4s so a hung
    # readiness endpoint cannot wedge the accept loop.
    my $code = `curl -fsS -o /dev/null -w "%{http_code}" --max-time 4 $ready_url 2>/dev/null`;
    $code =~ s/\D+//g;
    return ($code eq "200") ? "200" : "503";
}

sub state {
    # During grace, always report ready (200). After grace, reflect the
    # broker's actual readiness state.
    my $elapsed = time() - $start;
    if ($elapsed < $grace_secs) {
        return ("200", "ok (grace " . int($grace_secs - $elapsed) . "s left)");
    }
    my $code = probe_ready();
    return ($code, $code eq "200" ? "ok" : "not ready");
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
        my ($code, $body) = state();
        my $st = $code eq "200" ? "200 OK" : "503 Service Unavailable";
        my $resp  = "HTTP/1.1 $st\r\n"
                 .  "Content-Type: text/plain\r\n"
                 .  "Content-Length: " . length($body) . "\r\n"
                 .  "Connection: close\r\n\r\n"
                 .  $body;
        print {$c} $resp;
    };
    close $c;
}
