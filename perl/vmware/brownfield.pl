#!/usr/bin/perl 

use strict;
use warnings;
use DBI;
use Data::Dumper;
use DateTime;
use DateTime::Format::MySQL;
use DateTime::Format::Strptime;

my $cliqrdb_database="brownfield";
my $cliqrdb_user="osmosix";
my $cliqrdb_password="osmosix";
my $cliqrdb_host = "localhost";

my ($sql,$vmId,$row,$vmName,$nCpu,$memory);
my $dbh=DBI->connect("DBI:mysql:dbname=$cliqrdb_database;host=$cliqrdb_host", "$cliqrdb_user", "$cliqrdb_password") or die $DBI::errstr;

## Function to trim the string ###
sub Trim($)
{
        my $string = shift;
        $string =~ s/^\s+//;
        $string =~ s/\s+$//;
        return $string;
}

## function to fetch the distinct vmlist from brownfield database ###
sub get_vmlist {
	$sql = "SELECT DISTINCT vmId FROM VM_DETAILS WHERE MONTH(vmCreateTime) = MONTH(NOW()) union distinct select distinct vmId from VM_DETAILS where vmDeleteTime is null AND vmCreateTime < NOW()";
	my $sth = $dbh->prepare($sql);
	$sth->execute;
	my @vmList;
	while ($row = $sth->fetchrow_arrayref()) {
		push (@vmList, "@$row[0]");
	}
	return @vmList;
}

### Function to fetch the vm details from database ####
sub get_vmdetails {
	($vmId)=@_;
	my $sql = "SELECT vmId,vmName,nCpu,memory,vmCreateTime,vmDeleteTime FROM VM_DETAILS WHERE vmId=\"$vmId\"";
	my @row = $dbh->selectrow_array($sql);
	unless (@row) { die "VM details not found in database"; }
	my ($vmId,$vmName,$nCpu,$memory,$vmCreateTime,$vmDeleteTime) = @row;
	return $vmId,$vmName,$nCpu,$memory,$vmCreateTime,$vmDeleteTime;
	
}

#### Function to fetch the storage details from database ###
sub get_storage {
	($vmId)=@_;
	my $sql = "SELECT SUM(storage) FROM VM_STORAGE_DETAILS WHERE vmId=\"$vmId\"";
	my @row = $dbh->selectrow_array($sql);
	unless (@row) { die "Storage details not found in database"; }
	my ($storage) = @row;
	return $storage;
}

### Function to get cost input details from prop file ####
sub get_cost_input {
        my $cfg_file = "/usr/local/cliqr/etc/brownfield.properties";
	my ($each_line,$name,$value,%config,@values);
        if ( ! -f $cfg_file ) {
                print "$cfg_file not found";
        }

        undef %config;
        open CFGFILE,"<","$cfg_file" or Print_Error("Cannot open $cfg_file for reading","error");

        while ( $each_line = <CFGFILE> ) {
                        next if ($each_line =~ m/^#/ );
                        next if ($each_line =~ m/^ ?+$/ );
                        ($name,@values) = split /=/,$each_line;
                        $value = Trim(join "=",@values);
                        chomp ( $value );
                        $name = Trim($name);
                        $config{$name} = $value;
        }
        close(CFGFILE);
        return %config;
}

### function to calculate cost for each component ###
sub calculate_cost {
	my($cost_per_unit,$units,$time)=@_;
	my $cost = int($cost_per_unit*$units*$time);
	return $cost;
}

### function to update the cost for each vm ###
sub update_result_csv {
        my $output_file = "/usr/local/cliqr/bin/billing.csv";
        my($result) = @_;
        open my $OUTFILE, ">>", $output_file or die "Can't open the result file: $!";
        print $OUTFILE $result;
        close $OUTFILE;
}

### main ###
update_result_csv("VMNAME,Start Time, End Time,Hours of Running,No of CPU,CPU cost,Disk size in GB,Disk cost,RAM in GB,RAM Cost,Total cost\n");
my @vm_list = get_vmlist();
foreach (@vm_list) { 
	$vmId = $_;
	my ($end_time);

	my @vmdetails = get_vmdetails($vmId);
	my $storage = get_storage($vmId);
	my %cost = get_cost_input;

	my $start_time = DateTime::Format::MySQL->parse_datetime($vmdetails[4]);
	if ( defined $vmdetails[5] && $vmdetails[5] ne '' ) {
		$end_time = DateTime::Format::MySQL->parse_datetime($vmdetails[5]);
	}else { 
		$end_time=DateTime->now;
	}
	my $diff = $end_time->delta_ms($start_time);

	my $run_time = $diff->hours();
	my $storage_in_gb = int($storage/1048576);
	$nCpu = $vmdetails[2];
	$memory = int($vmdetails[3]/1024);
	$vmName = $vmdetails[1];

	my $cpuCost = calculate_cost($cost{'cpu_cost'},$nCpu,$run_time);
	my $storageCost = calculate_cost($cost{'storage_cost'},$storage_in_gb,$run_time);
	my $memoryCost = calculate_cost($cost{'memory_cost'},$memory,$run_time);

	my $total_cost = $cpuCost + $storageCost + $memoryCost;
	if ( defined $vmdetails[5] && $vmdetails[5] ne '' ) {
                $end_time = DateTime::Format::MySQL->parse_datetime($vmdetails[5]);
        }else {
                $end_time="running";
        }
	update_result_csv("$vmName,$start_time,$end_time,$run_time,$nCpu,$cpuCost,$storage_in_gb,$storageCost,$memory,$memoryCost,$total_cost\n");
	print "The VM name :".$vmName."\n";
	print "The cpu cost :".$cpuCost."\n";	
	print "The Disk of the vm is ".$storage_in_gb."GB and it costs :".$storageCost."USD \n";	
	print "The RAM  of the vm is ".$memory."GB and its costs :".$memoryCost."\n";	
}

exit 0;
