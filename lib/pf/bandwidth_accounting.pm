package pf::bandwidth_accounting;

=head1 NAME

pf::bandwidth_accounting -

=head1 DESCRIPTION

pf::bandwidth_accounting

=cut

use strict;
use warnings;
use Exporter qw(import);
our @EXPORT_OK = qw(bandwidth_maintenance);
use pf::dal::bandwidth_accounting;
use pf::dal::bandwidth_accounting_history;
use pf::dal::node;
use pf::error qw(is_error is_success);
use pf::log;
use pf::config qw($ACCOUNTING_POLICY_BANDWIDTH);
use pf::constants::trigger qw($TRIGGER_TYPE_ACCOUNTING);
use pf::config::security_event;
my $logger = get_logger();

sub bandwidth_maintenance {
    my ($batch, $time_limit, $window, $history_batch, $history_timeout, $history_window) = @_;
    process_bandwidth_accounting($batch, $time_limit);
    trigger_bandwidth($batch, $time_limit);
    bandwidth_aggregation_hourly($batch, $window, $time_limit);
    bandwidth_aggregation_history_daily($batch, $time_limit);
    bandwidth_aggregation_history_monthly($batch, $time_limit);
    bandwidth_accounting_history_cleanup($history_window, $history_batch, $history_timeout);
}

sub trigger_bandwidth {
    my ($batch, $time) = @_;
    if (@BANDWIDTH_EXPIRED_SECURITY_EVENTS > 0) {
        my ($status, $iter) = pf::dal::node->search(
            -where => {
                bandwidth_balance => 0,
                status => 'reg',
            },
            -columns => ['mac'],
            -with_class => undef,
        );
        if (is_success($status)) {
            while (my $row = $iter->next(undef)) {
                security_event_trigger(
                    {
                        'mac'  => $row->{mac},
                        'tid'  => $ACCOUNTING_POLICY_BANDWIDTH,
                        'type' => $TRIGGER_TYPE_ACCOUNTING
                    }
                );
            }
        }
    }
}

sub bandwidth_aggregation_hourly {
    my ($batch, $time_limit, $window) = @_;
    my $start_time = time;
    my $end_time;
    my $rows_deleted = 0;
    while (1) {
        my $rows = call_bandwidth_aggregation_hourly($batch, $window);
        $end_time = time;
        $rows_deleted+=$rows if $rows > 0;
        last if $rows <= 0 || (( $end_time - $start_time) > $time_limit );
    }

    $logger->info("aggregated $rows_deleted for bandwidth_aggregation_hourly ($start_time $end_time) ");
}

sub bandwidth_aggregation_history_daily {
    my ($batch, $time_limit) = @_;
    my $start_time = time;
    my $end_time;
    my $rows_deleted = 0;
    while (1) {
        my $rows = call_bandwidth_aggregation_history_daily($batch);
        $end_time = time;
        $rows_deleted+=$rows if $rows > 0;
        last if $rows <= 0 || (( $end_time - $start_time) > $time_limit );
    }

    $logger->info("aggregated $rows_deleted for bandwidth_aggregation_daily ($start_time $end_time) ");
}

sub bandwidth_aggregation_history_monthly {
    my ($batch, $time_limit) = @_;
    my $start_time = time;
    my $end_time;
    my $rows_deleted = 0;
    while (1) {
        my $rows = call_bandwidth_aggregation_history_monthly($batch);
        $end_time = time;
        $rows_deleted+=$rows if $rows > 0;
        last if $rows <= 0 || (( $end_time - $start_time) > $time_limit );
    }

    $logger->info("aggregated $rows_deleted for bandwidth_aggregation_monthly ($start_time $end_time) ");
}

sub process_bandwidth_accounting {
    my ($batch, $time_limit) = @_;
    my $start_time = time;
    my $end_time;
    my $rows_deleted = 0;
    while (1) {
        my $rows = call_process_bandwidth_accounting($batch);
        $end_time = time;
        $rows_deleted+=$rows if $rows > 0;
        last if $rows <= 0 || (( $end_time - $start_time) > $time_limit );
    }

    $logger->info("processed $rows_deleted for process_bandwidth_accounting ($start_time $end_time) ");
}

sub call_process_bandwidth_accounting {
    my ($batch) = @_;
    my $sql = "CALL process_bandwidth_accounting(?);";
    my ($status, $sth) = pf::dal::bandwidth_accounting->db_execute($sql, $batch);
    if (is_error($status)) {
        $logger->error("Error calling process_bandwidth_accounting");
        return 0;
    } else {
        my ($count) = $sth->fetchrow_array();
        $sth->finish;
        return $count;
    }
}

sub call_bandwidth_aggregation_hourly {
    my ($batch, $window) = @_;
    my $sql = "CALL bandwidth_aggregation(SUBDATE(NOW(), INTERVAL ? SECOND), ?);";
    my ($status, $sth) = pf::dal::bandwidth_accounting->db_execute($sql, $window, $batch);
    if (is_error($status)) {
        $logger->error("Error calling bandwidth_aggregation");
        return 0;
    } else {
        my ($count) = $sth->fetchrow_array();
        $sth->finish;
        return $count;
    }
}

sub call_bandwidth_aggregation_history_daily {
    my ($batch) = @_;
    my $sql = "CALL bandwidth_aggregation_history('daily', SUBDATE(NOW(), INTERVAL ? DAY), ?);";
    my ($status, $sth) = pf::dal::bandwidth_accounting->db_execute($sql, 1, $batch);
    if (is_error($status)) {
        $logger->error("Error calling bandwidth_aggregation_history");
        return 0;
    } else {
        my ($count) = $sth->fetchrow_array();
        $sth->finish;
        return $count;
    }
}

sub call_bandwidth_aggregation_history_monthly {
    my ($batch) = @_;
    my $sql = "CALL bandwidth_aggregation_history('monthly', SUBDATE(NOW(), INTERVAL ? MONTH), ?);";
    my ($status, $sth) = pf::dal::bandwidth_accounting->db_execute($sql, 1, $batch);
    if (is_error($status)) {
        $logger->error("Error calling bandwidth_aggregation_history");
        return 0;
    } else {
        my ($count) = $sth->fetchrow_array();
        $sth->finish;
        return $count;
    }
}

=head2 bandwidth_accounting_history_cleanup

bandwidth_accounting_history_cleanup

=cut

sub bandwidth_accounting_history_cleanup {
    my ($window_seconds, $batch, $time_limit) = @_;
    if ($window_seconds eq "0") {
        $logger->debug("Not deleting because the window is 0");
        return;
    }

    my $now = pf::dal->now();
    my ($status, $rows) = pf::dal::bandwidth_accounting_history->batch_remove(
        {
            -where => {
                time_bucket => {
                    "<" => \[ 'DATE_SUB(?, INTERVAL ? SECOND)', $now, $window_seconds ]
                },
            },
            -limit => $batch,
        },
        $time_limit
    );

    return $rows;
}

=head1 AUTHOR

Inverse inc. <info@inverse.ca>

=head1 COPYRIGHT

Copyright (C) 2005-2020 Inverse inc.

=head1 LICENSE

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301,
USA.

=cut

1;

