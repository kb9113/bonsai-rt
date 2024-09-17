package device
import vk "vendor:vulkan"
import "core:mem"
import "core:slice"

FeatureSet :: struct
{
    required_physical_device_extentions : []cstring,
    feature_chain : []rawptr
}

std_ray_trace_feature_set :: proc() -> FeatureSet
{
    ans := FeatureSet{}

    ans.required_physical_device_extentions = slice.clone([]cstring{
        vk.KHR_SWAPCHAIN_EXTENSION_NAME,
        vk.KHR_SHADER_NON_SEMANTIC_INFO_EXTENSION_NAME,
        vk.KHR_16BIT_STORAGE_EXTENSION_NAME,
        vk.KHR_ACCELERATION_STRUCTURE_EXTENSION_NAME,
        vk.KHR_RAY_TRACING_PIPELINE_EXTENSION_NAME,
        vk.KHR_DEFERRED_HOST_OPERATIONS_EXTENSION_NAME,
        vk.KHR_RAY_QUERY_EXTENSION_NAME,
        vk.KHR_RAY_TRACING_POSITION_FETCH_EXTENSION_NAME
    })

    feature_chain := make([dynamic]rawptr)

    ray_traceing_postion_fetch_features := &make([]vk.PhysicalDeviceRayTracingPositionFetchFeaturesKHR, 1)[0]
    ray_traceing_postion_fetch_features.sType = vk.StructureType.PHYSICAL_DEVICE_RAY_TRACING_POSITION_FETCH_FEATURES_KHR
    ray_traceing_postion_fetch_features.rayTracingPositionFetch = true
    append(&feature_chain, ray_traceing_postion_fetch_features)

    ray_queary_features := &make([]vk.PhysicalDeviceRayQueryFeaturesKHR, 1)[0]
    ray_queary_features.sType = vk.StructureType.PHYSICAL_DEVICE_RAY_QUERY_FEATURES_KHR
    ray_queary_features.rayQuery = true
    ray_queary_features.pNext = ray_traceing_postion_fetch_features
    append(&feature_chain, ray_queary_features)

    ray_traceing_pipeline_features := &make([]vk.PhysicalDeviceRayTracingPipelineFeaturesKHR, 1)[0]
    ray_traceing_pipeline_features.sType = vk.StructureType.PHYSICAL_DEVICE_RAY_TRACING_PIPELINE_FEATURES_KHR
    ray_traceing_pipeline_features.rayTracingPipeline = true
    ray_traceing_pipeline_features.pNext = ray_queary_features
    append(&feature_chain, ray_traceing_pipeline_features)

    ray_acceleration_structure_features := &make([]vk.PhysicalDeviceAccelerationStructureFeaturesKHR, 1)[0]
    ray_acceleration_structure_features.sType = vk.StructureType.PHYSICAL_DEVICE_ACCELERATION_STRUCTURE_FEATURES_KHR
    ray_acceleration_structure_features.accelerationStructure = true
    ray_acceleration_structure_features.pNext = ray_traceing_pipeline_features
    append(&feature_chain, ray_acceleration_structure_features)

    device_vulkan12_features := &make([]vk.PhysicalDeviceVulkan12Features, 1)[0]
    device_vulkan12_features.sType = vk.StructureType.PHYSICAL_DEVICE_VULKAN_1_2_FEATURES
    device_vulkan12_features.shaderFloat16 = true
    device_vulkan12_features.shaderInt8 = true
    device_vulkan12_features.shaderSampledImageArrayNonUniformIndexing = true
    device_vulkan12_features.runtimeDescriptorArray = true
    device_vulkan12_features.descriptorBindingVariableDescriptorCount = true
    device_vulkan12_features.descriptorBindingPartiallyBound = true
    device_vulkan12_features.bufferDeviceAddress = true
    device_vulkan12_features.pNext = ray_acceleration_structure_features
    append(&feature_chain, device_vulkan12_features)

    device_16_bit_storeage_features := &make([]vk.PhysicalDevice16BitStorageFeatures, 1)[0]
    device_16_bit_storeage_features.sType = vk.StructureType.PHYSICAL_DEVICE_16BIT_STORAGE_FEATURES
    device_16_bit_storeage_features.uniformAndStorageBuffer16BitAccess = true
    device_16_bit_storeage_features.storageBuffer16BitAccess = true
    device_16_bit_storeage_features.pNext = device_vulkan12_features
    append(&feature_chain, device_16_bit_storeage_features)

    ans.feature_chain = feature_chain[:]
    return ans
}

delete_feature_set :: proc(feature_set : FeatureSet)
{
    for r in feature_set.feature_chain
    {
        free(r)
    }
    delete(feature_set.feature_chain)
    delete(feature_set.required_physical_device_extentions)
}
