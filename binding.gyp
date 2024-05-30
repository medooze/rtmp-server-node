{
	'variables':
	{
		'external_libmediaserver%'		: '<!(echo $LIBMEDIASERVER)',
		'external_libmediaserver_include_dirs%'	: '<!(echo $LIBMEDIASERVER_INCLUDE)',
		'medooze_media_server_src' : "<!(node -e \"require('medooze-media-server-src')\")",
	},
	"targets": 
	[
		{
			"target_name": "medooze-rtmp-server",
			"cflags": 
			[
				"-march=native",
				"-fexceptions",
				"-O3",
				"-g",
				"-Wno-unused-function -Wno-comment",
				#"-O0",
				#"-fsanitize=address,leak"
			],
			"cflags_cc": 
			[
				"-fexceptions",
				"-std=c++17",
				"-O3",
				"-g",
				"-Wno-unused-function",
				#"-O0",
				#"-fsanitize=address,leak"
			],
			"include_dirs" : 
			[
				'/usr/include/nodejs/',
				"<!(node -e \"require('nan')\")"
			],
			"ldflags" : [" -lpthread -lresolv"],
			"link_settings": 
			{
        			'libraries': ["-lpthread -lpthread -lresolv"]
      			},
			"sources": 
			[ 
				"src/rtmp-server_wrap.cxx",
			],
			"conditions":
			[
				[
					"external_libmediaserver == ''", 
					{
						"include_dirs" :
						[
							'<(medooze_media_server_src)/include',
							'<(medooze_media_server_src)/src',
							'<(medooze_media_server_src)/ext/crc32c/include',
							'<(medooze_media_server_src)/ext/libdatachannels/src',
							'<(medooze_media_server_src)/ext/libdatachannels/src/internal',
							'<(node_root_dir)/deps/openssl/openssl/include'
						],
						"sources": 
						[
							"<(medooze_media_server_src)/src/DependencyDescriptorLayerSelector.cpp",
							"<(medooze_media_server_src)/src/EventLoop.cpp",
							"<(medooze_media_server_src)/src/log.cpp",
							"<(medooze_media_server_src)/src/PacketHeader.cpp",
							"<(medooze_media_server_src)/src/MacAddress.cpp",
							"<(medooze_media_server_src)/src/utf8.cpp",
							"<(medooze_media_server_src)/src/avcdescriptor.cpp",
							"<(medooze_media_server_src)/src/MediaFrameListenerBridge.cpp",
							"<(medooze_media_server_src)/src/rtp/LayerInfo.cpp",
							"<(medooze_media_server_src)/src/rtp/RTPPacket.cpp",
							"<(medooze_media_server_src)/src/rtp/RTPPayload.cpp",
							"<(medooze_media_server_src)/src/rtp/RTPHeader.cpp",
							"<(medooze_media_server_src)/src/rtp/RTPHeaderExtension.cpp",
							"<(medooze_media_server_src)/src/rtp/RTPMap.cpp",
							"<(medooze_media_server_src)/src/rtmp/rtmpserver.cpp",
							"<(medooze_media_server_src)/src/rtmp/amf.cpp",
							"<(medooze_media_server_src)/src/rtmp/rtmpclientconnection.cpp",
							"<(medooze_media_server_src)/src/rtmp/rtmpmessage.cpp",
							"<(medooze_media_server_src)/src/rtmp/rtmpserver.cpp",
							"<(medooze_media_server_src)/src/rtmp/rtmpconnection.cpp",
							"<(medooze_media_server_src)/src/rtmp/rtmpstream.cpp",
							"<(medooze_media_server_src)/src/rtmp/rtmpnetconnection.cpp",
							"<(medooze_media_server_src)/src/rtmp/rtmpchunk.cpp",
							"<(medooze_media_server_src)/src/rtmp/rtmppacketizer.cpp",
							"<(medooze_media_server_src)/src/VideoLayerSelector.cpp",
							"<(medooze_media_server_src)/src/h264/H264LayerSelector.cpp",
							"<(medooze_media_server_src)/src/h265/HEVCDescriptor.cpp",
							"<(medooze_media_server_src)/src/h265/h265.cpp",
							"<(medooze_media_server_src)/src/vp8/VP8LayerSelector.cpp",
							"<(medooze_media_server_src)/src/vp9/VP9LayerSelector.cpp",
							"<(medooze_media_server_src)/src/av1/AV1CodecConfigurationRecord.cpp",
							"<(medooze_media_server_src)/src/av1/AV1LayerSelector.cpp",
							"<(medooze_media_server_src)/src/av1/Obu.cpp",
						],
  					        "conditions" : [
								['OS=="mac"', {
									"xcode_settings": {
										"CLANG_CXX_LIBRARY": "libc++",
										"CLANG_CXX_LANGUAGE_STANDARD": "c++17",
										"GCC_ENABLE_CPP_EXCEPTIONS": "YES",
										"OTHER_CFLAGS": [ "-Wno-c++11-narrowing","-Wno-aligned-allocation-unavailable","-march=native"]
									},
								}]
						]
					},
					{
						"libraries"	: [ "<(external_libmediaserver)" ],
						"include_dirs"	: [ "<@(external_libmediaserver_include_dirs)" ],
						'conditions':
						[
							['OS=="linux"', {
								"ldflags" : [" -Wl,-Bsymbolic "],
							}],
							['OS=="mac"', {
									"xcode_settings": {
										"CLANG_CXX_LIBRARY": "libc++",
										"CLANG_CXX_LANGUAGE_STANDARD": "c++17",
										"OTHER_CFLAGS": [ "-Wno-aligned-allocation-unavailable","-march=native"]
									},
							}],
						]
					}
				]
			]
		}
	]
}

