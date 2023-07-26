{
	'variables':
	{
		'external_libmediaserver%'		: '<!(echo $LIBMEDIASERVER)',
		'external_libmediaserver_include_dirs%'	: '<!(echo $LIBMEDIASERVER_INCLUDE)',
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
							'media-server/include',
							'media-server/src',
							'media-server/ext/crc32c/include',
							'media-server/ext/libdatachannels/src',
							'media-server/ext/libdatachannels/src/internal',
							'<(node_root_dir)/deps/openssl/openssl/include'
						],
						"sources": 
						[
							"media-server/src/EventLoop.cpp",
							"media-server/src/PacketHeader.cpp",
							"media-server/src/MacAddress.cpp",
							"media-server/src/utf8.cpp",
							"media-server/src/avcdescriptor.cpp",
							"media-server/src/MediaFrameListenerBridge.cpp",
							"media-server/src/rtp/LayerInfo.cpp",
							"media-server/src/rtp/RTPPacket.cpp",
							"media-server/src/rtp/RTPPayload.cpp",
							"media-server/src/rtp/RTPHeader.cpp",
							"media-server/src/rtp/RTPHeaderExtension.cpp",
							"media-server/src/rtp/RTPMap.cpp",
							"media-server/src/rtmp/rtmpserver.cpp",
							"media-server/src/rtmp/amf.cpp",
							"media-server/src/rtmp/rtmpclientconnection.cpp",
							"media-server/src/rtmp/rtmpmessage.cpp",
							"media-server/src/rtmp/rtmpserver.cpp",
							"media-server/src/rtmp/rtmpconnection.cpp",
							"media-server/src/rtmp/rtmpstream.cpp",
							"media-server/src/rtmp/rtmpnetconnection.cpp",
							"media-server/src/rtmp/rtmpchunk.cpp",
							"media-server/src/rtmp/rtmppacketizer.cpp",
							"media-server/src/VideoLayerSelector.cpp",
							"media-server/src/h264/H264LayerSelector.cpp",
							"media-server/src/h265/HEVCDescriptor.cpp",
							"media-server/src/h265/h265.cpp",
							"media-server/src/vp8/VP8LayerSelector.cpp",
							"media-server/src/vp9/VP9LayerSelector.cpp",
							"media-server/src/av1/AV1CodecConfigurationRecord.cpp",
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

