package resource
import vk "vendor:vulkan"
import "core:fmt"
import "core:slice"
import "core:c/libc"
import "core:mem"
import "../device"

AccelerationStructure :: struct
{
    buffer : StorageBufferInfo(u8),
    acceleration_structure : vk.AccelerationStructureKHR
}

to_generic_buffer_acceleration_structure :: proc(acceleration_structure : AccelerationStructure) -> GenericResource
{
    ans := GenericAccelerationStructure{}
    ans.acceleration_structure = acceleration_structure.acceleration_structure
    return GenericResource(ans)
}

delete_acceleration_structure :: proc(device_context : ^device.DeviceContext, acceleration_structure : AccelerationStructure)
{
    vk.DestroyAccelerationStructureKHR(
        device_context.device,
        acceleration_structure.acceleration_structure,
        nil
    )
    delete_storage_buffer(device_context, acceleration_structure.buffer)
}

get_buffer_device_address :: proc(device_context : ^device.DeviceContext, buffer : vk.Buffer) -> vk.DeviceAddress
{
    buffer_device_ai := vk.BufferDeviceAddressInfo{}
	buffer_device_ai.sType = vk.StructureType.BUFFER_DEVICE_ADDRESS_INFO
	buffer_device_ai.buffer = buffer
	ans := vk.GetBufferDeviceAddress(device_context.device, &buffer_device_ai)
	return ans
}

get_acceleration_structure_device_address :: proc(device_context : ^device.DeviceContext, acceleration_structure : vk.AccelerationStructureKHR) -> vk.DeviceAddress
{
    acceleration_device_ai := vk.AccelerationStructureDeviceAddressInfoKHR{}
	acceleration_device_ai.sType = vk.StructureType.ACCELERATION_STRUCTURE_DEVICE_ADDRESS_INFO_KHR
	acceleration_device_ai.accelerationStructure = acceleration_structure;
    ans := vk.GetAccelerationStructureDeviceAddressKHR(device_context.device, &acceleration_device_ai)
    return ans
}

create_bottom_level_acceleration_structure :: proc(
    device_context : ^device.DeviceContext,
    vertex_buffer : StorageBufferInfo([4]f32),
    index_buffer : StorageBufferInfo(u32)
) -> AccelerationStructure
{
    acceleration_structure_geometry := vk.AccelerationStructureGeometryKHR{}
    acceleration_structure_geometry.sType = vk.StructureType.ACCELERATION_STRUCTURE_GEOMETRY_KHR
	acceleration_structure_geometry.flags = {vk.GeometryFlagKHR.OPAQUE}
	acceleration_structure_geometry.geometryType = vk.GeometryTypeKHR.TRIANGLES
	acceleration_structure_geometry.geometry.triangles.sType = vk.StructureType.ACCELERATION_STRUCTURE_GEOMETRY_TRIANGLES_DATA_KHR
	acceleration_structure_geometry.geometry.triangles.vertexFormat = vk.Format.R32G32B32_SFLOAT
	acceleration_structure_geometry.geometry.triangles.vertexData.deviceAddress = get_buffer_device_address(
	   device_context, vertex_buffer.buffer
	)

	acceleration_structure_geometry.geometry.triangles.maxVertex = u32(vertex_buffer.buffer_size / size_of([4]f32)) - 1
	acceleration_structure_geometry.geometry.triangles.vertexStride = size_of([4]f32)
	acceleration_structure_geometry.geometry.triangles.indexType = vk.IndexType.UINT32
	acceleration_structure_geometry.geometry.triangles.indexData.deviceAddress = get_buffer_device_address(
        device_context, index_buffer.buffer
    )
	acceleration_structure_geometry.geometry.triangles.transformData.deviceAddress = 0
	acceleration_structure_geometry.geometry.triangles.transformData.hostAddress = nil

	acceleration_structure_build_geometry_info := vk.AccelerationStructureBuildGeometryInfoKHR{}
	acceleration_structure_build_geometry_info.sType = vk.StructureType.ACCELERATION_STRUCTURE_BUILD_GEOMETRY_INFO_KHR
	acceleration_structure_build_geometry_info.type = vk.AccelerationStructureTypeKHR.BOTTOM_LEVEL
	acceleration_structure_build_geometry_info.flags = {vk.BuildAccelerationStructureFlagKHR.PREFER_FAST_TRACE}
	acceleration_structure_build_geometry_info.geometryCount = 1;
	acceleration_structure_build_geometry_info.pGeometries = &acceleration_structure_geometry;

	acceleration_structure_build_sizes_info := vk.AccelerationStructureBuildSizesInfoKHR{}
	acceleration_structure_build_sizes_info.sType = vk.StructureType.ACCELERATION_STRUCTURE_BUILD_SIZES_INFO_KHR
	num_triangles := u32(index_buffer.buffer_size / size_of(u32) / 3)
	vk.GetAccelerationStructureBuildSizesKHR(
	    device_context.device,
		vk.AccelerationStructureBuildTypeKHR.DEVICE,
		&acceleration_structure_build_geometry_info,
		&num_triangles,
		&acceleration_structure_build_sizes_info
	)

	//
	ans := AccelerationStructure{}
	ans.buffer = make_storage_buffer(
	    device_context,
		u8, u32(acceleration_structure_build_sizes_info.accelerationStructureSize),
		{vk.BufferUsageFlag.ACCELERATION_STRUCTURE_STORAGE_KHR, vk.BufferUsageFlag.SHADER_DEVICE_ADDRESS}
	)

	// Acceleration structure
	acceleration_structure_create_info := vk.AccelerationStructureCreateInfoKHR{}
	acceleration_structure_create_info.sType = vk.StructureType.ACCELERATION_STRUCTURE_CREATE_INFO_KHR
	acceleration_structure_create_info.buffer = ans.buffer.buffer
	acceleration_structure_create_info.size = acceleration_structure_build_sizes_info.accelerationStructureSize
	acceleration_structure_create_info.type = vk.AccelerationStructureTypeKHR.BOTTOM_LEVEL

	vk.CreateAccelerationStructureKHR(
	    device_context.device,
		&acceleration_structure_create_info,
		nil,
		&ans.acceleration_structure
	)

	// AS device address
	acceleration_device_address_info := vk.AccelerationStructureDeviceAddressInfoKHR{}
	acceleration_device_address_info.sType = vk.StructureType.ACCELERATION_STRUCTURE_DEVICE_ADDRESS_INFO_KHR
	acceleration_device_address_info.accelerationStructure = ans.acceleration_structure

	acceleration_device_address := get_acceleration_structure_device_address(
	    device_context, ans.acceleration_structure
	);

	// create scratch buffer for building the bottom level acceleration structure
	scratch_buffer := make_storage_buffer(
        device_context,
        u8, u32(acceleration_structure_build_sizes_info.buildScratchSize),
        {vk.BufferUsageFlag.SHADER_DEVICE_ADDRESS}
	)

	acceleration_build_geometry_info := vk.AccelerationStructureBuildGeometryInfoKHR{}
	acceleration_build_geometry_info.sType = vk.StructureType.ACCELERATION_STRUCTURE_BUILD_GEOMETRY_INFO_KHR
	acceleration_build_geometry_info.type = vk.AccelerationStructureTypeKHR.BOTTOM_LEVEL
	acceleration_build_geometry_info.flags = {vk.BuildAccelerationStructureFlagKHR.PREFER_FAST_TRACE}
	acceleration_build_geometry_info.mode = vk.BuildAccelerationStructureModeKHR.BUILD
	acceleration_build_geometry_info.dstAccelerationStructure = ans.acceleration_structure
	acceleration_build_geometry_info.geometryCount = 1
	acceleration_build_geometry_info.pGeometries = &acceleration_structure_geometry
	acceleration_build_geometry_info.scratchData.deviceAddress = get_buffer_device_address(
	    device_context, scratch_buffer.buffer
	)

	acceleration_structure_build_range_info := vk.AccelerationStructureBuildRangeInfoKHR{}
	acceleration_structure_build_range_info.primitiveCount = num_triangles;
	acceleration_structure_build_range_info.primitiveOffset = 0;
	acceleration_structure_build_range_info.firstVertex = 0;
	acceleration_structure_build_range_info.transformOffset = 0;
	acceleration_build_structure_range_infos := []vk.AccelerationStructureBuildRangeInfoKHR{
	    acceleration_structure_build_range_info
    }
    acceleration_build_structure_range_info_raw_data := raw_data(acceleration_build_structure_range_infos)

    command_buffer := device.begin_single_time_command(device_context)
    vk.CmdBuildAccelerationStructuresKHR(
        command_buffer,
        1,
        &acceleration_build_geometry_info,
        &acceleration_build_structure_range_info_raw_data
    )
    device.end_single_time_command(device_context, &command_buffer)

    return ans
}

AccelerationStructureInstance :: struct
{
    acceleration_structure : AccelerationStructure,
    transform : matrix[4, 4]f32
}

create_top_level_acceleration_structure :: proc(
    device_context : ^device.DeviceContext,
    bottom_level_acceleration_structures : []AccelerationStructureInstance
) -> AccelerationStructure
{
    instance_buffer_host_cohearent := make_host_coherent_buffer(
        device_context, vk.AccelerationStructureInstanceKHR, u32(len(bottom_level_acceleration_structures))
    )

    instance_storeage_buffer := make_storage_buffer(
        device_context, vk.AccelerationStructureInstanceKHR, u32(len(bottom_level_acceleration_structures)),
        {
            vk.BufferUsageFlag.SHADER_DEVICE_ADDRESS,
            vk.BufferUsageFlag.ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_KHR,
            vk.BufferUsageFlag.TRANSFER_DST
        }
    )

    for i in 0..<len(bottom_level_acceleration_structures)
    {
        acceleration_structure := vk.AccelerationStructureInstanceKHR{}
        for x in 0..<3
        {
            for y in 0..<4
            {
                acceleration_structure.transform.mat[x][y] = bottom_level_acceleration_structures[i].transform[x, y]
            }
        }

        acceleration_structure.instanceCustomIndexAndMask = (u32(0xFF) << 24) | 0
        acceleration_structure.instanceShaderBindingTableRecordOffsetAndFlags = u32(vk.GeometryInstanceFlagKHR.TRIANGLE_FACING_CULL_DISABLE) << 24 | 0
        acceleration_structure.accelerationStructureReference = u64(get_acceleration_structure_device_address(
            device_context, bottom_level_acceleration_structures[i].acceleration_structure.acceleration_structure
        ))

        instance_buffer_host_cohearent.data[i] = acceleration_structure
    }

    copy_host_cohernet_buffer_to_storage_buffer(
        device_context,
        instance_buffer_host_cohearent,
        instance_storeage_buffer
    )

    acceleration_structure_geometry := vk.AccelerationStructureGeometryKHR{}
    acceleration_structure_geometry.sType = vk.StructureType.ACCELERATION_STRUCTURE_GEOMETRY_KHR
    acceleration_structure_geometry.geometryType = vk.GeometryTypeKHR.INSTANCES
    acceleration_structure_geometry.flags = {vk.GeometryFlagKHR.OPAQUE}
    acceleration_structure_geometry.geometry.instances.sType = vk.StructureType.ACCELERATION_STRUCTURE_GEOMETRY_INSTANCES_DATA_KHR
    acceleration_structure_geometry.geometry.instances.arrayOfPointers = false
    acceleration_structure_geometry.geometry.instances.data.deviceAddress = get_buffer_device_address(
        device_context, instance_storeage_buffer.buffer
    )

    acceleration_structure_build_geometry_info := vk.AccelerationStructureBuildGeometryInfoKHR{}
    acceleration_structure_build_geometry_info.sType = vk.StructureType.ACCELERATION_STRUCTURE_BUILD_GEOMETRY_INFO_KHR
	acceleration_structure_build_geometry_info.type = vk.AccelerationStructureTypeKHR.TOP_LEVEL
	acceleration_structure_build_geometry_info.flags = {vk.BuildAccelerationStructureFlagKHR.PREFER_FAST_TRACE}
	acceleration_structure_build_geometry_info.geometryCount = 1
	acceleration_structure_build_geometry_info.pGeometries = &acceleration_structure_geometry

	acceleration_structure_build_sizes_info := vk.AccelerationStructureBuildSizesInfoKHR{}
	acceleration_structure_build_sizes_info.sType = vk.StructureType.ACCELERATION_STRUCTURE_BUILD_SIZES_INFO_KHR
	primitive_count := u32(len(bottom_level_acceleration_structures));
	vk.GetAccelerationStructureBuildSizesKHR(
		device_context.device,
		vk.AccelerationStructureBuildTypeKHR.DEVICE,
		&acceleration_structure_build_geometry_info,
		&primitive_count,
		&acceleration_structure_build_sizes_info
	);

	ans := AccelerationStructure{}
	ans.buffer = make_storage_buffer(
	    device_context,
		u8, u32(acceleration_structure_build_sizes_info.accelerationStructureSize),
		{vk.BufferUsageFlag.ACCELERATION_STRUCTURE_STORAGE_KHR, vk.BufferUsageFlag.SHADER_DEVICE_ADDRESS}
	)

	// Acceleration structure
	acceleration_structure_create_info := vk.AccelerationStructureCreateInfoKHR{}
	acceleration_structure_create_info.sType = vk.StructureType.ACCELERATION_STRUCTURE_CREATE_INFO_KHR
	acceleration_structure_create_info.buffer = ans.buffer.buffer
	acceleration_structure_create_info.size = acceleration_structure_build_sizes_info.accelerationStructureSize
	acceleration_structure_create_info.type = vk.AccelerationStructureTypeKHR.TOP_LEVEL

	vk.CreateAccelerationStructureKHR(
	    device_context.device,
		&acceleration_structure_create_info,
		nil,
		&ans.acceleration_structure
	)

	// AS device address
	acceleration_device_address_info := vk.AccelerationStructureDeviceAddressInfoKHR{}
	acceleration_device_address_info.sType = vk.StructureType.ACCELERATION_STRUCTURE_DEVICE_ADDRESS_INFO_KHR
	acceleration_device_address_info.accelerationStructure = ans.acceleration_structure

	acceleration_device_address := get_acceleration_structure_device_address(
	    device_context, ans.acceleration_structure
	);

	// create scratch buffer for building the top level acceleration structure
	scratch_buffer := make_storage_buffer(
        device_context,
        u8, u32(acceleration_structure_build_sizes_info.buildScratchSize),
        {vk.BufferUsageFlag.SHADER_DEVICE_ADDRESS}
	)

	acceleration_build_geometry_info := vk.AccelerationStructureBuildGeometryInfoKHR{}
	acceleration_build_geometry_info.sType = vk.StructureType.ACCELERATION_STRUCTURE_BUILD_GEOMETRY_INFO_KHR
	acceleration_build_geometry_info.type = vk.AccelerationStructureTypeKHR.TOP_LEVEL
	acceleration_build_geometry_info.flags = {vk.BuildAccelerationStructureFlagKHR.PREFER_FAST_TRACE}
	acceleration_build_geometry_info.mode = vk.BuildAccelerationStructureModeKHR.BUILD
	acceleration_build_geometry_info.dstAccelerationStructure = ans.acceleration_structure
	acceleration_build_geometry_info.geometryCount = 1
	acceleration_build_geometry_info.pGeometries = &acceleration_structure_geometry
	acceleration_build_geometry_info.scratchData.deviceAddress = get_buffer_device_address(
	    device_context, scratch_buffer.buffer
	)

	acceleration_structure_build_range_info := vk.AccelerationStructureBuildRangeInfoKHR{}
	acceleration_structure_build_range_info.primitiveCount = primitive_count;
	acceleration_structure_build_range_info.primitiveOffset = 0;
	acceleration_structure_build_range_info.firstVertex = 0;
	acceleration_structure_build_range_info.transformOffset = 0;
	acceleration_build_structure_range_infos := []vk.AccelerationStructureBuildRangeInfoKHR{
	    acceleration_structure_build_range_info
    }
    acceleration_build_structure_range_info_raw_data := raw_data(acceleration_build_structure_range_infos)

    command_buffer := device.begin_single_time_command(device_context)
    vk.CmdBuildAccelerationStructuresKHR(
        command_buffer,
        1,
        &acceleration_build_geometry_info,
        &acceleration_build_structure_range_info_raw_data
    )
    device.end_single_time_command(device_context, &command_buffer)
    return ans
}
