

use strict;
use warnings;
use Term::ANSIColor;
use VMware::VIRuntime;
use VMware::VILib;
use DBI;
use Data::Dumper;
use Time::localtime;
use DateTime;    

my %opts = (
   'vmname' => {
      type => "=s",
      help => "Name of the virtual machine",
      required => 1,
   },
   'dbhost' => {
      type => "=s",
      help => "The ip of brownfield database host",
      required => 1,
   },
   'alarm_name' => {
      type => "=s",
      help => "Name of Alarm triggered",
      required => 1,
   },
);

$SIG{__DIE__} = sub{Util::disconnect();};


Opts::add_options(%opts);

# validate options, and connect to the server
Opts::parse();
Opts::validate();
Util::connect();

my ($vm_id,$vm_view,$vmname,$dbh,$alarm_name,$dbhost,@row,$row,$datacenter_view,$datacenter);

$vmname = Opts::get_option('vmname');
$dbhost = Opts::get_option('dbhost');
$alarm_name = Opts::get_option('alarm_name');

my $reportdb_database="brownfield";
my $reportdb_user="osmosix";
my $reportdb_password="osmosix";
my $reportdb_host = $dbhost;
my $vmCreateTime = "undef";

### Function to print the log file 
sub update_log {	
	my ($logstmt) = @_;
	open my $fh, ">>", '/tmp/logfile.txt' or die "Can't open the log file: $!";
	print $fh $logstmt;
	close $fh;

}
### Function to check the vm available in the database ###
sub check_vm {
	my($vmId) = @_;
	$dbh=DBI->connect("DBI:mysql:dbname=$reportdb_database;host=$reportdb_host", "$reportdb_user", "$reportdb_password") or die $DBI::errstr;
	my $vm_id;
	my $sth = $dbh->prepare("select vmId from  VM_DETAILS where vmId=\"$vmId\"");
	$sth->execute();
	while (@row = $sth->fetchrow_array) {  # retrieve one row
    		update_log("VMdetails updated during previous PowerOn for $vmId");
		$vm_id=$row[0];
	}
	$sth->finish();
	$dbh->disconnect();
	
 	print " Row is $vm_id\n";
	return $vm_id;
}

### Function to update the vm details in the database ###
sub update_vmdetails {
	my($vmId,$vmName,$nCpu,$memory,$vmCreateTime,$datacenter) = @_;
	$dbh=DBI->connect("DBI:mysql:dbname=$reportdb_database;host=$reportdb_host", "$reportdb_user", "$reportdb_password") or die $DBI::errstr;

	my $sth = $dbh->prepare("select * from  VM_DETAILS where vmId=\"$vmId\"");
	$sth->execute();
	$sth = $dbh->prepare("insert into VM_DETAILS (vmId,vmName,nCpu,memory,vmCreateTime,dataCenter) VALUES (\"$vmId\",\"$vmName\",\"$nCpu\",\"$memory\",\"$vmCreateTime\",\"$datacenter\") ON DUPLICATE KEY UPDATE vmDeleteTime=NULL;");
	$sth->execute();
	$sth->finish();
	$dbh->disconnect();
}

### Function to update the storage details in the database ###
sub update_storagedetails {
	my($vmId,$vmName,$disk_name,$storage) = @_;
	$dbh=DBI->connect("DBI:mysql:dbname=$reportdb_database;host=$reportdb_host", "$reportdb_user", "$reportdb_password") or die $DBI::errstr;

	my $sth = $dbh->prepare("insert into VM_STORAGE_DETAILS (vmId,vmName,diskName,storage) VALUES (\"$vmId\",\"$vmName\",\"$disk_name\",\"$storage\");");
	$sth->execute();
	$sth->finish();
	$dbh->disconnect();
}

### Function to update the delete time on vm termination ####
sub set_delete_time {
	my($vmId,$vmName,$delete_time) = @_;
	$dbh=DBI->connect("DBI:mysql:dbname=$reportdb_database;host=$reportdb_host", "$reportdb_user", "$reportdb_password") or die $DBI::errstr;

	my $sth = $dbh->prepare("update VM_DETAILS set vmDeleteTime=\"$delete_time\" where vmId=\"$vmId\"");
	$sth->execute();
	$sth->finish();
	$dbh->disconnect();
}


#### Main ####
$vm_view = Vim::find_entity_views(view_type => 'VirtualMachine',
                                         filter => {'config.name' => $vmname});
			#print Dumper($vm_view->parent);
   if (!@$vm_view) {
	update_log("\nThere is no virtual machine with name '$vmname' registered\n");
      Util::trace(0, "\nThere is no virtual machine with name '$vmname' registered\n");
      exit 0;
   }

        my $vmhosts = Vim::find_entity_views(view_type => 'Datacenter');
	foreach my $datacenter_view (@$vmhosts) {
   		my $datacenter = $datacenter_view->name;
		update_log("Datacenter: ".$datacenter."\n");
	}
#Uncomment the below line for first run 
#$vm_view = Vim::find_entity_views(view_type => 'VirtualMachine');
foreach( sort {$a->summary->config->name cmp $b->summary->config->name} @$vm_view) {
	if($_->summary->runtime->connectionState->val eq 'connected') {
		if(!$_->config->template) {
			$vmname = $_->summary->config;
			$vm_id = $_->{'mo_ref'}->value;
			#print Dumper($vm_id->runtime->host);
			update_log("VM Name: ".$vmname->name."\n");
			update_log("Num of CPU: ".$vmname->numCpu."\n");
			update_log("Memory: ".$vmname->memorySizeMB."\n");
			update_log("No of disks: ".$vmname->numVirtualDisks."\n");
			if ( $alarm_name eq "create_vm" ){
				$vmCreateTime = DateTime->now;
				my $vmAvailable = check_vm($vm_id);
				if($vm_id ne $vmAvailable){ 
				update_vmdetails($vm_id,$vmname->name,$vmname->numCpu,$vmname->memorySizeMB,$vmCreateTime,$datacenter);
				my $devices = $_->config->hardware->device;
				foreach(@$devices) {
				if($_->isa('VirtualDisk')) {
					my $label = $_->deviceInfo->label;
					my $disk_size = $_->capacityInKB;
					$disk_size =~ tr/,//d ;
					update_log("Disk Size of ".$label.": ".$disk_size."\n");
					update_storagedetails($vm_id,$vmname->name,$label,$disk_size);
					}
					}
				}
			}
			elsif ($alarm_name eq "delete_vm"){
				my $vmDeleteTime = DateTime->now;
				set_delete_time($vm_id,$vmname->name,$vmDeleteTime);
				next;
			}
		}
  	}
}

Util::disconnect();

exit 0;
