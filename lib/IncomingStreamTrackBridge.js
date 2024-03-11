const Native		= require("./Native");
const Emitter		= require("medooze-event-emitter");
const SharedPointer	= require("./SharedPointer");
const IncomingStreamBridge = require("./IncomingStreamBridge");
const LayerInfo		= require("./LayerInfo");

/**
 * @typedef {Object} LayerStats Information about each spatial/temporal layer (if present)
 * @property {number} simulcastIdx
 * @property {number} spatialLayerId Spatial layer id
 * @property {number} temporalLayerId Temporatl layer id
 * @property {number} [totalBytes] total rtp received bytes for this layer
 * @property {number} [numPackets] number of rtp packets received for this layer
 * @property {number} bitrate average bitrate received during last second for this layer
 * @property {number} totalBitrate average bitrate (media + overhead) received during last second in bps 
 * @property {number} [targetBitrate] signaled target bitrate on the VideoLayersAllocation header
 * @property {number} [targetWidth] signaled target width on the VideoLayersAllocation header
 * @property {number} [targetHeight] signaled target height on the VideoLayersAllocation header
 * @property {number} [targetFps] signaled target fps on the VideoLayersAllocation header 
 */

/**
 * @typedef {Object} MediaStats stats for each media stream
 * @property {number} [lostPackets] total lost packkets
 * @property {number} [lostPacketsDelta] total lost/out of order packets during last second
 * @property {number} [dropPackets] droppted packets by media server
 * @property {number} numFrames number of rtp packets received
 * @property {number} numFramesDelta number of rtp packets received during last seconds
 * @property {number} numPackets number of rtp packets received
 * @property {number} numPacketsDelta number of rtp packets received during last seconds
 * @property {number} [numRTCPPackets] number of rtcp packsets received
 * @property {number} totalBytes total rtp received bytes
 * @property {number} [totalRTCPBytes] total rtp received bytes
 * @property {number} [totalPLIs] total PLIs sent
 * @property {number} [totalNACKs] total NACk packets sent
 * @property {number} bitrate average bitrate received during last second in bps
 * @property {number} totalBitrate average bitrate (media + overhead) received during last second in bps 
 * @property {number} [skew] difference between NTP timestamp and RTP timestamps at sender (from RTCP SR)
 * @property {number} [drift] ratio between RTP timestamps and the NTP timestamp and  at sender (from RTCP SR)
 * @property {number} [clockRate] RTP clockrate
 * @property {number} [width] video width
 * @property {number} [height] video height
 * @property {number} [targetBitrate] signaled target bitrate
 * @property {number} [targetWidth] signaled target width
 * @property {number} [targetHeight] signaled target height
 * @property {number} [targetFps] signaled target fps
 * @property {LayerStats[]} layers Information about each spatial/temporal layer (if present).
 * @property {LayerStats[]} [individual] Information about each individual layer
 */

/**
 * @typedef PacketWaitTime packet waiting times in rtp buffer before delivering them
 * @property {number} min
 * @property {number} max
 * @property {number} avg
 */

/**
 * @typedef {Object} EncodingStats stats for each encoding (media, rtx sources (if used))
 *
 * @property {number} timestamp When this stats was generated (in order to save workload, stats are cached for 200ms)
 * @property {PacketWaitTime} waitTime 
 * @property {MediaStats} media Stats for the media stream
 * @property {{}} rtx Stats for the rtx retransmission stream
 * @property {number} [rtt] Round Trip Time in ms
 * @property {number} bitrate Bitrate for media stream only in bps
 * @property {number} totalBitrate average bitrate (media + overhead) received during last second in bps
 * @property {number} [remb] Estimated avialable bitrate for receving (only avaailable if not using tranport wide cc)
 * @property {number} simulcastIdx Simulcast layer index based on bitrate received (-1 if it is inactive).
 * @property {number} [lostPackets] Accumulated lost packets for rtx, media strems
 * @property {number} [lostPacketsRatio] Lost packets ratio
 * @property {number} [width] Video width
 * @property {number} [height] Video height
 * @property {number} [targetBitrate] signaled target bitrate
 * @property {number} [targetWidth] signaled target width
 * @property {number} [targetHeight] signaled target height
 * @property {number} [targetFps] signaled target fps
 * @property {number} [iframes] Total intra frames
 * @property {number} [iframesDelta] Intra frames per second
 * @property {number} [bframes] Total B frames
 * @property {number} [bframesDelta] B frames per second
 * @property {number} [pframes] Total P frames
 * @property {number} [pframesDelta] P frames per second
 * @property {string} [codec] Name of the codec last in use
 * 
 * Info accumulated for `rtx`, `media` streams:
 *
 * @property {number} numFrames
 * @property {number} numFramesDelta
 * @property {number} numPackets
 * @property {number} numPacketsDelta
 * 
 * @deprecated @property {number} total Accumulated bitrate in bps
 */

/** @typedef {{ [encodingId: string]: EncodingStats }} TrackStats providing the info for each source */

/**
 * @typedef {Object} Encoding
 * @property {string} id
 * @property {SharedPointer.Proxy<Native.MediaFrameListenerBridgeShared>} bridge
 * @property {SharedPointer.Proxy<Native.MediaFrameListenerBridgeShared>} source
 * @property {Native.RTPReceiverShared} receiver
 * @property {SharedPointer.Proxy<Native.MediaFrameListenerBridgeShared>} depacketizer
 */

/**
 * @typedef {Object} ActiveEncodingInfo
 * @property {string} id
 * @property {number} simulcastIdx
 * @property {number} bitrate
 * @property {number} totalBitrate average bitrate (media + overhead) received during last second in bps 
 * @property {LayerStats[]} layers
 * @property {number} [width]
 * @property {number} [height]
 * @property {number} [targetBitrate] signaled target bitrate on the VideoLayersAllocation header
 * @property {number} [targetWidth] signaled target width on the VideoLayersAllocation header
 * @property {number} [targetHeight] signaled target height on the VideoLayersAllocation header
 * @property {number} [targetFps] signaled target fps on the VideoLayersAllocation header
 */

/**
 * @typedef {Object} ActiveLayersInfo Active layers object containing an array of active and inactive encodings and an array of all available layer info
 * @property {ActiveEncodingInfo[]} active
 * @property {Array<LayerStats & { encodingId: string }>} layers
 * @property {{ id: string }[]} inactive
 */

/**
 * @typedef {Object} IncomingStreamTrackBridgeEvents
 * @property {(self: IncomingStreamTrackBridge) => void} attached
 * @property {(self: IncomingStreamTrackBridge) => void} detached
 * @property {(self: IncomingStreamTrackBridge) => void} stopped
 * @property {(muted: boolean) => void} muted
 */

/** @returns {MediaStats} */
function getMediaStatsFromMediaBridge(/** @type {SharedPointer.Proxy<Native.MediaFrameListenerBridgeShared> */ bridge)
{
	 //Get media stats from bridge stats
	return /** @type {MediaStats} */ {
		numPackets	: bridge.numPackets,
		numPacketsDelta	: bridge.numPacketsDelta,
		numFrames	: bridge.numFrames,
		numFramesDelta	: bridge.numFramesDelta,
		totalBytes	: bridge.totalBytes,
		bitrate		: bridge.bitrate,
		totalBitrate	: bridge.bitrate,
		layers		: []
	};
}

/** @returns {EncodingStats} */
function getEncodingStatsFromMediaBridge(/** @type {SharedPointer.Proxy<Native.MediaFrameListenerBridgeShared> */ bridge)
{
	//Get stats for sourrces	
	const mediaStats = getMediaStatsFromMediaBridge(bridge);

	/** @type {EncodingStats} */
	const stats = {
		waitTime : {
			min	: bridge.minWaitedTime,
			max	: bridge.maxWaitedTime,
			avg	: bridge.avgWaitedTime,
		},
		media		: mediaStats,
		rtx		: {},
		numPackets	: mediaStats.numPacketsDelta,
		numPacketsDelta	: mediaStats.numPacketsDelta,
		numFrames	: mediaStats.numFrames,
		numFramesDelta	: mediaStats.numFramesDelta,
		bitrate		: mediaStats.bitrate,
		totalBitrate	: mediaStats.bitrate,
		total		: mediaStats.bitrate,
		timestamp	: Date.now(),
		simulcastIdx	: -1,
		codec		: mediaStats.numFrames ? bridge.codec : undefined,
	};

	//If we have i/p/b info
	if (bridge.iframes || bridge.pframes || bridge.bframes)
	{
		stats.iframes		= bridge.iframes;
		stats.iframesDelta	= bridge.iframesDelta;
		stats.bframes		= bridge.bframes;
		stats.bframesDelta	= bridge.bframesDelta;
		stats.pframes		= bridge.pframes;
		stats.pframesDelta	= bridge.pframesDelta;
	}
		
	//If we have size
	if (bridge.width > 0 && bridge.height > 0)
	{
		stats.width	= bridge.width;
		stats.height	= bridge.height;
	}

	//Done
	return stats;
}

/** @returns {ActiveLayersInfo} */
function getActiveLayersFromStats(/** @type {TrackStats} */ stats)
{
	const active	= /** @type {ActiveLayersInfo['active']} */ ([]);
	const inactive  = /** @type {ActiveLayersInfo['inactive']} */ ([]);
	const all	= /** @type {ActiveLayersInfo['layers']} */ ([]);

	//For all encodings
	for (const id in stats)
	{
		//If it is inactive
		if (!stats[id].bitrate)
		{
			//Add to inactive encodings
			inactive.push({
				id: id
			});
			//skip
			continue;
		}
			
		//Append to encodings
		const encoding = /** @type {ActiveEncodingInfo} */ ({
			id		: id,
			simulcastIdx	: stats[id].simulcastIdx,
			bitrate		: stats[id].bitrate,
			totalBitrate	: stats[id].totalBitrate,
			layers		: []
		});
			
		//Add optional attributes
		if (stats[id].media.targetBitrate>0)
			encoding.targetBitrate	=  stats[id].media.targetBitrate;
		if (stats[id].media.targetWidth>0)
			encoding.targetWidth	=  stats[id].media.targetWidth;
		if (stats[id].media.targetHeight>0)
			encoding.targetHeight	=  stats[id].media.targetHeight;
		if (stats[id].media.targetFps>0)
			encoding.targetFps	= stats[id].media.targetFps;

		//Check if we have width and height
		if (stats[id].media.width && stats[id].media.height)
		{
			//Set them
			encoding.width = stats[id].media.width;
			encoding.height = stats[id].media.height;
		}
			
		//Get layers
		const layers = stats[id].media.layers; 
			
		//For each layer
		for (const layer of layers)
		{

			//Append to encoding
			encoding.layers.push({
				simulcastIdx	: layer.simulcastIdx,
				spatialLayerId	: layer.spatialLayerId,
				temporalLayerId	: layer.temporalLayerId,
				bitrate		: layer.bitrate,
				totalBitrate	: layer.totalBitrate,
				targetBitrate	: layer.targetBitrate,
				targetWidth	: layer.targetWidth,
				targetHeight	: layer.targetHeight,
				targetFps	: layer.targetFps
			});
				
			//Append to all layer list
			all.push({
				encodingId	: id,
				simulcastIdx	: layer.simulcastIdx,
				spatialLayerId	: layer.spatialLayerId,
				temporalLayerId	: layer.temporalLayerId,
				bitrate		: layer.bitrate,
				totalBitrate	: layer.totalBitrate,
				targetBitrate	: layer.targetBitrate,
				targetWidth	: layer.targetWidth,
				targetHeight	: layer.targetHeight,
				targetFps	: layer.targetFps
			});
		}
			
		//Check if the encoding had svc layers
		if (encoding.layers.length)
			//Order layer list based on bitrate
			encoding.layers = encoding.layers.sort(sortByBitrateReverse);
		else
			//Add encoding as layer
			all.push({
				encodingId	: encoding.id,
				simulcastIdx	: encoding.simulcastIdx,
				spatialLayerId	: LayerInfo.MaxLayerId,
				temporalLayerId	: LayerInfo.MaxLayerId,
				bitrate		: encoding.bitrate,
				totalBitrate	: encoding.totalBitrate,
				targetBitrate	: encoding.targetBitrate,
				targetWidth	: encoding.targetWidth,
				targetHeight	: encoding.targetHeight,
				targetFps	: encoding.targetFps
			});
				
		//Add to encoding list
		active.push(encoding);
	}
		
	//Return ordered info
	return {
		active		: active.sort(sortByBitrateReverse),
		inactive	: inactive, 
		layers		: all.sort(sortByBitrateReverse)
	};
}


function sortByBitrate(/** @type {EncodingStats|LayerStats|ActiveEncodingInfo} */ a, /** @type {EncodingStats|LayerStats|ActiveEncodingInfo} */ b)
{
	return a.targetBitrate && b.targetBitrate 
		? a.targetBitrate - b.targetBitrate 
		: a.bitrate - b.bitrate;
}

function sortByBitrateReverse(/** @type {EncodingStats|LayerStats|ActiveEncodingInfo} */ a, /** @type {EncodingStats|LayerStats|ActiveEncodingInfo} */ b)
{
	return a.targetBitrate && b.targetBitrate 
		? b.targetBitrate - a.targetBitrate 
		: b.bitrate - a.bitrate;
}

function updateStatsSimulcastIndex(/** @type {TrackStats} */ stats)
{
	//Set simulcast index
	let simulcastIdx = 0;
		
	//Order the encodings in reverse order
	for (let stat of Object.values(stats).sort(sortByBitrate))
	{
		//Set simulcast index if the encoding is active
		stat.simulcastIdx = stat.bitrate ? simulcastIdx++ : -1;
		//For all layers
		for (const layer of stat.media.layers)
			//Set it also there
			layer.simulcastIdx = stat.simulcastIdx;
		for (const layer of stat.media.individual || [])
			//Set it also there
			layer.simulcastIdx = stat.simulcastIdx;
	}
}

/**
 * Audio or Video track of a remote media stream
 * @extends {Emitter<IncomingStreamTrackBridgeEvents>}
 */
class IncomingStreamTrackBridge extends Emitter
{
	/**
	 * @ignore
	 * @hideconstructor
	 * private constructor
	 */
	constructor(
		/** @type {"audio" | "video"} */ media,
		/** @type {string} */ id,
		/** @type {SharedPointer.Proxy<Native.MediaFrameListenerBridgeShared>} */ bridge,
		/** @type {IncomingStreamBridge} */ stream)
	{
		super();
		
		//Store track info
		this.media	= media;
		this.id		= id;
		this.bridge     = bridge;
		//Attach counter
		this.counter	= 0;
		
		this.muted = false;
		
		//Create source map
		this.encodings = /** @type {Map<string, Encoding>} */ (new Map());
		
		//Push new encoding
		this.encodings.set("", {
			id		: "",
			bridge		: bridge,
			source		: bridge,
			receiver	: bridge.toRTPReceiver(),
			depacketizer	: bridge
		});

		//Set global depacketizer
		this.depacketizer = this.getDefaultEncoding().depacketizer;
		this.stream = stream;
	}
	
	/**
	 * Check if the track is muted or not
	 * @returns {boolean} muted
	 */
	isMuted()
	{
		return this.muted;
	}

	/*
	 * Mute/Unmute track
	 * @param {boolean} muting - if we want to mute or unmute
	 */
	/**
	 * @param {boolean} muting
	 */
	mute(muting) 
	{
		//For each source
		for (let encoding of this.encodings.values())
		{
			//Mute encoding
			encoding.source.Mute(muting);
		}
		
		//If we are different
		if (this.muted!==muting)
		{
			//Store it
			this.muted = muting;
			this.emit("muted",this.muted);
		}
	}

	/**
	 * Get stats for all encodings
	 * @returns {Promise<TrackStats>}
	 */
	async getStatsAsync()
	{
		//Check if we have cachedd stats
		if (!this.stats )
			//Create new stats
			this.stats = /** @type {TrackStats} */ ({});
		
		//For each source ordered by bitrate (reverse)
		for (let encoding of this.encodings.values())
		{
			const { id, bridge } = encoding;

			//Check if we have cachedd stats
			if (!this.stats[id] || (Date.now() - this.stats[id].timestamp)>200 )
			{
				//Update stats async
				await new Promise(resolve=>bridge.UpdateAsync({resolve}));
				//Get encoding stats from bridge
				this.stats[id] = getEncodingStatsFromMediaBridge(bridge)
				//Add rtt from stream
				this.stats[id].rtt =  this.stream.stream?.getRTT() || 0;
			}
		}
		
		//Update silmulcast index for layers
		updateStatsSimulcastIndex(this.stats);
		
		//Return a clone of cached stats;
		return Object.assign({},this.stats);
	}
	
	/**
	 * Get stats for all encodings
	 * @returns {TrackStats}
	 */
	getStats()
	{
		//Check if we have cachedd stats
		if (!this.stats )
			//Create new stats
			this.stats = /** @type {TrackStats} */ ({});
		
		//For each source ordered by bitrate (reverse)
		for (let encoding of this.encodings.values())
		{
			const { id, bridge } = encoding;

			//Check if we have cachedd stats
			if (!this.stats[id] || (Date.now() - this.stats[id].timestamp)>200 )
			{
				//Update stats
				bridge.Update();
				//Get encoding stats from bridge
				this.stats[id] = getEncodingStatsFromMediaBridge(bridge)
				//Add rtt from stream
				this.stats[id].rtt =  this.stream.stream?.getRTT() || 0;
			}
		}
		
		//Update silmulcast index for layers
		updateStatsSimulcastIndex(this.stats);
		
		//Return a clone of cached stats;
		return Object.assign({},this.stats);
	}
	
	/**
	 * Get active encodings and layers ordered by bitrate
	 * @returns {ActiveLayersInfo} Active layers object containing an array of active and inactive encodings and an array of all available layer info
	 */
	getActiveLayers()
	{
		//Get track stats
		const stats = this.getStats();
		
		//Get active layers from stats
		return getActiveLayersFromStats(stats);
	}

	/**
	 * Get active encodings and layers ordered by bitrate
	 * @returns {Promise<ActiveLayersInfo>} Active layers object containing an array of active and inactive encodings and an array of all available layer info
	 */
	async getActiveLayersAsync()
	{
		//Get track stats
		const stats = await this.getStatsAsync();
		
		//Get active layers from stats
		return getActiveLayersFromStats(stats);
	}

	/**
	* Get track id as signaled on the SDP
	*/
	getId()
	{
		return this.id;
	}
	
	/**
	 * Return ssrcs associated to this track
	 */
	getSSRCs()
	{
		const ssrcs = /** @type {{ [encodingId: string]: { media: number } }} */ ({});
		
		//For each source
		for (let encoding of this.encodings.values())
			//Push new encoding
			ssrcs[encoding.id] = {
				media : encoding.bridge.GetMediaSSRC(),
			};
		//Return the stats array
		return ssrcs;
	}
	
	/**
	* Get track media type
	* @returns {"audio"|"video"}
	*/
	getMedia()
	{
		return this.media;
	}
	
	/**
	 * Get all track encodings
	 * Internal use, you'd beter know what you are doing before calling this method
	 * @returns {Array<Encoding>} - encodings 
	 **/
	getEncodings()
	{
		return Array.from(this.encodings.values());
	}

	/**
	 * Get encoding by id
	 * Internal use, you'd beter know what you are doing before calling this method
	 * @param {String} encodingId	- encoding Id,
	 * @returns {Encoding | undefined}
	 **/
	getEncoding(encodingId)
	{
		return this.encodings.get(encodingId);
	}
	
	/**
	 * Get default encoding
	 * Internal use, you'd beter know what you are doing before calling this method
	 * @returns {Encoding}
	 **/
	getDefaultEncoding()
	{
		return [...this.encodings.values()][0];
	}

	/**
	 * Signal that this track has been attached.
	 * Internal use, you'd beter know what you are doing before calling this method
	 */
	attached() 
	{
		//Increase attach counter
		this.counter++;
		
		//If it is the first
		if (this.counter===1)
			this.emit("attached",this);
	}
	
	/** 
	 * Request an intra refres on all sources
	 */
	refresh()
	{
		//Not implemented for rtmp
	}
	
	/**
	 * Signal that this track has been detached.
	 * Internal use, you'd beter know what you are doing before calling this method
	 */
	detached()
	{
		//Decrease attach counter
		this.counter--;
		
		//If it is the last
		if (this.counter===0)
			this.emit("detached",this);
	}

	/**
	 * Set the target bitrate hint for VLA
	 * @param {Number} targetBitrateHint	-  target bitrate hint in kbps
	 */
	setTargetBitrateHint(targetBitrateHint)
	{
		this.bridge.SetTargetBitrateHint(targetBitrateHint);
	}
	
	/**
	 * Removes the track from the incoming stream and also detaches any attached outgoing track or recorder
	 */
	stop()
	{
		//Don't call it twice
		if (this.stopped) return;

		//Stopped
		this.stopped = true;
		
		this.emit("stopped",this);

		//stop event emitter
		super.stop();
		
		//remove encodings
		this.encodings.clear();
		
		//Null stuff
		//@ts-expect-error
		this.depacketizer = null;
		//@ts-expect-error
		this.bridge = null;
	}

}

module.exports = IncomingStreamTrackBridge;
