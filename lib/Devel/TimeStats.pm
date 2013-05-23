package Devel::TimeStats;

use Moo;
use namespace::autoclean;
use Time::HiRes qw/gettimeofday tv_interval/;
use Text::ANSITable;
use Tree::Simple qw/use_weak_refs/;
use Tree::Simple::Visitor::FindByUID;

has enable => (is => 'rw', required => 1, default => sub{ 1 });

has tree => (
             is => 'ro',
             required => 1,
             default => sub{ Tree::Simple->new({t => [gettimeofday]}) },
             handles => [qw/ accept traverse /],
            );
has stack => (
              is => 'ro',
              required => 1,
              lazy => 1,
              default => sub { [ shift->tree ] }
             );

has color_schema => (
    is => 'ro',
    isa => sub{ ref $_ eq 'HASH' },
    default => sub{{
        '0.01' => 'aaaa00', 
        '0.05' => 'FFFF00',
        '0.1'  => 'aa0000',
        '0.5'  => 'FF0000',
    }}
);

sub profile {
    my $self = shift;

    return unless $self->enable;

    my %params;
    if (@_ <= 1) {
        $params{comment} = shift || "";
    }
    elsif (@_ % 2 != 0) {
        die "profile() requires a single comment parameter or a list of name-value pairs; found "
            . (scalar @_) . " values: " . join(", ", @_);
    }
    else {
        (%params) = @_;
        $params{comment} ||= "";
    }

    my $parent;
    my $prev;
    my $t = [ gettimeofday ];
    my $stack = $self->stack;

    if ($params{end}) {
        # parent is on stack; search for matching block and splice out
        for (my $i = $#{$stack}; $i > 0; $i--) {
            if ($stack->[$i]->getNodeValue->{action} eq $params{end}) {
                my ($node) = splice(@{$stack}, $i, 1);
                # Adjust elapsed on partner node
                my $v = $node->getNodeValue;
                $v->{elapsed} =  tv_interval($v->{t}, $t);
                return $node->getUID;
            }
        }
    # if partner not found, fall through to treat as non-closing call
    }
    if ($params{parent}) {
        # parent is explicitly defined
        $prev = $parent = $self->_get_uid($params{parent});
    }
    if (!$parent) {
        # Find previous node, which is either previous sibling or parent, for ref time.
        $prev = $parent = $stack->[-1] or return undef;
        my $n = $parent->getChildCount;
        $prev = $parent->getChild($n - 1) if $n > 0;
    }

    my $node = Tree::Simple->new({
        action  => $params{begin} || "",
        t => $t,
        elapsed => tv_interval($prev->getNodeValue->{t}, $t),
        comment => $params{comment},
    });
    $node->setUID($params{uid}) if $params{uid};

    $parent->addChild($node);
    push(@{$stack}, $node) if $params{begin};

    return $node->getUID;
}

sub created {
    return @{ shift->{tree}->getNodeValue->{t} };
}

sub elapsed {
    return tv_interval(shift->{tree}->getNodeValue->{t});
}

sub report {
    my $self = shift;
    
    my $total_duration = tv_interval($self->tree->getNodeValue->{t});

    my $column_width = 80;
    #my $t = Text::SimpleTable->new( [ $column_width, 'Action' ], [ 9, 'Time' ] );
    my $t = Text::ANSITable->new( use_utf8 => 0 );
    
    $t->columns([qw/ Action Time % /]);
    my @results;
    $self->traverse(
                sub {
                my $action = shift;
                my $stat   = $action->getNodeValue;
                my @r = ( $action->getDepth,
                      ($stat->{action} || "") .
                      ($stat->{action} && $stat->{comment} ? " " : "") . ($stat->{comment} ? '- ' . $stat->{comment} : ""),
                      $stat->{elapsed},
                      $stat->{action} ? 1 : 0,
                      );
                # Trim down any times >= 10 to avoid ugly Text::Simple line wrapping
                my $elapsed = substr(sprintf("%f", $stat->{elapsed}), 0, 8) . "s";
                
                my $color = '';
                foreach my $key (sort { $a <=> $b } keys %{$self->color_schema}) {
                    $color = $self->color_schema->{$key} if $stat->{elapsed} >= $key;                    
                }
                
                # calc %
                my $share = sprintf "%2.1f%%", ($stat->{elapsed} * 100) / $total_duration;
                
                $t->add_row([( q{ } x $r[0] ) . $r[1], defined $r[2] ? $elapsed : '??', $share], { fgcolor => $color });
                push(@results, \@r);
                }
            );
    return wantarray ? @results : $t->draw;
}

sub _get_uid {
    my ($self, $uid) = @_;

    my $visitor = Tree::Simple::Visitor::FindByUID->new;
    $visitor->searchForUID($uid);
    $self->accept($visitor);
    return $visitor->getResult;
}

sub addChild {
    my $self = shift;
    my $node = $_[ 0 ];

    my $stat = $node->getNodeValue;

    # do we need to fake $stat->{ t } ?
    if( $stat->{ elapsed } ) {
        # remove the "s" from elapsed time
        $stat->{ elapsed } =~ s{s$}{};
    }

    $self->tree->addChild( @_ );
}

sub setNodeValue {
    my $self = shift;
    my $stat = $_[ 0 ];

    # do we need to fake $stat->{ t } ?
    if( $stat->{ elapsed } ) {
        # remove the "s" from elapsed time
        $stat->{ elapsed } =~ s{s$}{};
    }

    $self->tree->setNodeValue( @_ );
}

sub getNodeValue {
    my $self = shift;
    $self->tree->getNodeValue( @_ )->{ t };
}




1;
__END__

=encoding utf-8

=head1 NAME

Devel::TimeStats - Yet Another Timing Statistics Class

=head1 SYNOPSIS

    use Devel::TimeStats;
    
    my $ts = Devel::TimeStats->new;
    
    $ts->profile( begin => 'some task');
    
    do_foo();
    
    $ts->profile('done foo');
        
    do_bar();
    
    $ts->profile('done bar');
        
    $ts->profile( end => 'some task');
    
    
    
    

=head1 DESCRIPTION

Devel::TimeStats is ...

=head1 LICENSE

Copyright (C) Carlos Fernando Avila Gratz.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Carlos Fernando Avila Gratz E<lt>cafe@q1software.comE<gt>

=cut

