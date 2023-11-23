const Native		= require("./Native");
const Emitter		= require("medooze-event-emitter");
const SharedPointer	= require("./SharedPointer");

/**
 * @typedef {Object} LayerStats Information about each spatial/temporal layer (if present)
 * @property {number} simulcastIdx
 * @property {number} spatialLayerId Spatial layer id
 * @property {number} temporalLayerId Temporatl layer id
 * @property {number} [totalBytes] total rtp received bytes for this layer
 * @property {number} [numPackets] number of rtp packets received for this layer
 * @property {number} bitrate average bitrate received during last second for this layer
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
 * @property {number} [skew] difference between NTP timestamp and RTP timestamps at sender (from RTCP SR)
 * @property {number} [drift] ratio between RTP timestamps and the NTP timestamp and  at sender (from RTCP SR)
 * @property {number} [clockRate] RTP clockrate
 * @property {LayerStats[]} layers Information about each spatial/temporal layer (if present)
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
 * 
 * @property {number} [rtt] Round Trip Time in ms
 * @property {number} bitrate Bitrate for media stream only in bps
 * @property {number} total Accumulated bitrate for rtx, media streams in bps
 * @property {number} [remb] Estimated avialable bitrate for receving (only avaailable if not using tranport wide cc)
 * @property {number} simulcastIdx Simulcast layer index based on bitrate received (-1 if it is inactive).
 * @property {number} [lostPackets] Accumulated lost packets for rtx, media strems
 * @property {number} [lostPacketsRatio] Lost packets ratio
 * @property {number} [width] Video width
 * @property {number} [height] Video height
 * @property {number} [iframes] Total intra frames
 * @property {number} [iframesDelta] Intra frames per second
 * @property {number} [bframes] Total B frames
 * @property {number} [bframesDelta] B frames per second
 * @property {number} [pframes] Total P frames
 * @property {number} [pframesDelta] P frames per second
 * @property {number} [codec] Enumeration identifying the type of codec in use (See media-server codec.h for details)
 * 
 * 
 *
 * Info accumulated for `rtx`, `media` streams:
 *
 * @property {number} numFrames
 * @property {number} numFramesDelta
 * @property {number} numPackets
 * @property {number} numPacketsDelta
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
 * @property {LayerStats[]} layers
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
 */

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
		/** @type {SharedPointer.Proxy<Native.MediaFrameListenerBridgeShared>} */ bridge)
	{
		super();

		//Store track info
		this.media	= media;
		this.id		= id;
		this.bridge     = bridge;
		//Attach counter
		this.counter	= 0;
	
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
				//Push new encoding
				const mediaStats = /** @type {MediaStats} */ ({
					numPackets	: bridge.numPackets,
					numPacketsDelta	: bridge.numPacketsDelta,
					numFrames	: bridge.numFrames,
					numFramesDelta	: bridge.numFramesDelta,
					totalBytes	: bridge.totalBytes,
					bitrate		: bridge.bitrate,
					layers		: []
				});
				this.stats[id] = {
					waitTime : {
						min		: bridge.minWaitedTime,
						max		: bridge.maxWaitedTime,
						avg		: bridge.avgWaitedTime,
					},
					media	 : mediaStats,
					rtx	 : {},
					// accumulated bitrate
					numPackets: mediaStats.numPacketsDelta,
					numPacketsDelta: mediaStats.numPacketsDelta,
					numFrames: mediaStats.numFrames,
					numFramesDelta: mediaStats.numFramesDelta,
					bitrate: mediaStats.bitrate,
					total: mediaStats.bitrate,
					// timestamps
					timestamp: Date.now(),
					// provisional (set below)
					simulcastIdx: -1,
				};
				
				if (bridge.width > 0 && bridge.height > 0)
				{
					this.stats[id].width = bridge.width;
					this.stats[id].height = bridge.height;
					this.stats[id].iframes = bridge.iframes;
					this.stats[id].iframesDelta = bridge.iframesDelta;
					this.stats[id].bframes = bridge.bframes;
					this.stats[id].bframesDelta = bridge.bframesDelta;
					this.stats[id].pframes = bridge.pframes;
					this.stats[id].pframesDelta = bridge.pframesDelta;
				}

				if (bridge.codec != Native.UNKNOWN_CODEC)
				{
					this.stats[id].codec = bridge.codec;
				}
			}
		}
		
		//Set simulcast index
		let simulcastIdx = 0;
		
		//Order the encodings in reverse order
		for (let stat of Object.values(this.stats).sort((a,b)=>a.bitrate-b.bitrate))
		{
			//Set simulcast index if the encoding is active
			stat.simulcastIdx = stat.bitrate ? simulcastIdx++ : -1;
			//For all layers
			for (const layer of stat.media.layers)
				//Set it also there
				layer.simulcastIdx = stat.simulcastIdx;
		}
		
		//Return a clone of cached stats;
		return Object.assign({},this.stats);
	}
	
	/**
	 * Get active encodings and layers ordered by bitrate
	 * @returns {ActiveLayersInfo}
	 */
	getActiveLayers()
	{
		const active	= /** @type {ActiveLayersInfo['active']} */ ([]);
		const inactive  = /** @type {ActiveLayersInfo['inactive']} */ ([]);
		const all	= /** @type {ActiveLayersInfo['layers']} */ ([]);
		
		//Get track stats
		const stats = this.getStats();
		
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
				layers		: []
			});
			
			//Get layers
			const layers = stats[id].media.layers; 
			
			//For each layer
			for (let i=0;i<layers.length;++i)
			{

				//Append to encoding
				encoding.layers.push({
					simulcastIdx	: layers[i].simulcastIdx,
					spatialLayerId	: layers[i].spatialLayerId,
					temporalLayerId	: layers[i].temporalLayerId,
					bitrate		: layers[i].bitrate
				});
				
				//Append to all layer list
				all.push({
					encodingId	: id,
					simulcastIdx	: layers[i].simulcastIdx,
					spatialLayerId	: layers[i].spatialLayerId,
					temporalLayerId	: layers[i].temporalLayerId,
					bitrate		: layers[i].bitrate
				});
			}
			
			//Check if the encoding had svc layers
			if (encoding.layers.length)
				//Order layer list based on bitrate
				encoding.layers = encoding.layers.sort((a, b) => b.bitrate-a.bitrate);
			else
				//Add encoding as layer
				all.push({
					encodingId	: encoding.id,
					simulcastIdx	: encoding.simulcastIdx,
					spatialLayerId	: 255,
					temporalLayerId	: 255,
					bitrate		: encoding.bitrate
				});
				
			//Add to encoding list
			active.push(encoding);
		}
		
		//Return ordered info
		return {
			active		: active.sort((a, b) => b.bitrate-a.bitrate),
			inactive	: inactive, 
			layers		: all.sort((a, b) => b.bitrate-a.bitrate)
		};
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
