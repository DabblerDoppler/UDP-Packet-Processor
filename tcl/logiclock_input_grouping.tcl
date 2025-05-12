# Parameters
set y_anchors {6 33 61 88 115 142 169 196}
set region_height 12
set region_width 2
set region_x 139
set group_size 32

for {set group 0} {$group < 8} {incr group} {
    set low_bit [expr {$group * $group_size}]
    set high_bit [expr {$low_bit + $group_size - 1}]
    set y_start [lindex $y_anchors $group]
    set region_name "ll_region_grp$group"

    # Properly escaped signal names
    set in_data     "in_data\\\[$low_bit:$high_bit\\\]"
    set in_data_d1  "in_data_d1\\\[$low_bit:$high_bit\\\]"
    set in_keep     "in_keep\\\[$low_bit:$high_bit\\\]"
    set in_keep_d1  "in_keep_d1\\\[$low_bit:$high_bit\\\]"

    # Create LogicLock region and assign signals
    set_instance_assignment -name LOGICLOCK_REGION $region_name -to "$in_data"
    set_instance_assignment -name LOGICLOCK_REGION $region_name -to "$in_data_d1"
    set_instance_assignment -name LOGICLOCK_REGION $region_name -to "$in_keep"
    set_instance_assignment -name LOGICLOCK_REGION $region_name -to "$in_keep_d1"

    # Assign in_valid/in_valid_d1 and in_last/in_last_d1 to the first region only
    if {$group == 0} {
        set_instance_assignment -name LOGICLOCK_REGION $region_name -to in_valid
        set_instance_assignment -name LOGICLOCK_REGION $region_name -to in_valid_d1
        set_instance_assignment -name LOGICLOCK_REGION $region_name -to in_last
        set_instance_assignment -name LOGICLOCK_REGION $region_name -to in_last_d1
    }

    # Define location, size, and mode
    set_location_assignment LOGICLOCK_REGION_X${region_x}_Y${y_start} -to $region_name
    set_instance_assignment -name LOGICLOCK_REGION_SIZE ${region_width}x${region_height} -to $region_name
    set_instance_assignment -name LOGICLOCK_REGION_MODE SOFT -to $region_name
}