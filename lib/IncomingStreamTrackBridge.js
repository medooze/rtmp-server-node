const Native		= require("./Native");
const EventEmitter	= require("events").EventEmitter;

/**
 * Audio or Video track of a remote media stream
 */
class IncomingStreamTrackBridge
{
	/**
	 * @ignore
	 * @hideconstructor
	 * private constructor
	 */
	constructor(media,id,receiver,source)
	{
		//Store track info
		this.id		= id;
		this.media	= media;
		this.receiver	= receiver;
		//Not muted
		this.muted	= false;
		//Attach counter
		this.counter	= 0;
	
		//Create source map
		this.encodings = new Map();
		
		//Push new encoding
		this.encodings.set("", {
			id		: "",
			source		: source,
			receiver	: this.receiver,
			depacketizer	: source
		});

		//Set global depacketizer
		this.depacketizer = this.encodings.values().next().value.depacketizer;
		
		//Create event emitter
		this.emitter = new EventEmitter();
	}
	
	/**
	 * Get stats for all encodings 
	 * 
	 * For each encoding you will get stats for media, rtx sources (if used):
	 *  - media    : Stats for the media stream
	 *  - rtx      : Stats for the rtx retransmission stream
	 *  - rtt      : Round Trip Time in ms
	 *  - waitTime : "min","max" and "avg" packet waiting times in rtp buffer before delivering them
	 *  - bitrate  : Bitrate for media stream only in bps
	 *  - total    : Accumulated bitrate for rtx, media streams in bps
	 *  - remb     : Estimated avialable bitrate for receving (only avaailable if not using tranport wide cc)
	 *  - timestamp: When this stats was generated, in order to save workload, stats are cached for 200ms
	 *  - simulcastIdx	: Simulcast layer index based on bitrate received (-1 if it is inactive).
	 *  - lostPackets	: Accumulated lost packets for rtx, media strems
	 *  - numPackets	: Accumulated packets for rtx, media strems
	 *  - lostPacketsRatio	: Lost packets ratio
	 * 
	 * The stats objects will provide the follwing info for each source
	 *  - lostPackets	: total lost packkets
	 *  - lostPacketsDelta	: total lost/out of order packets during last second
	 *  - dropPackets       : droppted packets by media server
	 *  - numFrames		: number of rtp packets received
	 *  - numFramesDelta	: number of rtp packets received during last seconds
	 *  - numPackets	: number of rtp packets received
	 *  - numPacketsDelta	: number of rtp packets received during last seconds
	 *  - numRTCPPackets	: number of rtcp packsets received
	 *  - totalBytes	: total rtp received bytes
	 *  - totalRTCPBytes	: total rtp received bytes
	 *  - totalPLIs		: total PLIs sent
	 *  - totalNACKs	: total NACk packets sent
	 *  - bitrate		: average bitrate received during last second in bps
	 *  - skew		: difference between NTP timestamp and RTP timestamps at sender (from RTCP SR)
	 *  - drift		: ratio between RTP timestamps and the NTP timestamp and  at sender (from RTCP SR)
	 *  - clockRate		: RTP clockrate
	 *  - layers		: Information about each spatial/temporal layer (if present)
	 *    * spatialLayerId  : Spatial layer id
	 *    * temporalLayerId : Temporatl layer id
	 *    * totalBytes	: total rtp received bytes for this layer
	 *    * numPackets	: number of rtp packets received for this layer
	 *    * bitrate		: average bitrate received during last second for this layer
	 *  
	 * @returns {Map<String,Object>} Map with stats by encodingId
	 */
	getStats()
	{
		//Check if we have cachedd stats
		if (!this.stats )
			//Create new stats
			this.stats = {};
		
		//For each source ordered by bitrate (reverse)
		for (let encoding of this.encodings.values())
		{
			//Check if we have cachedd stats
			if (!this.stats[encoding.id] || (Date.now() - this.stats[encoding.id].timestamp)>200 )
			{
				//Update stats
				encoding.source.Update();
				//Push new encoding
				this.stats[encoding.id] = {
					waitTime : {
						min		: encoding.source.minWaitedTime,
						max		: encoding.source.maxWaitedTime,
						avg		: encoding.source.avgWaitedTime,
					},
					media	 : {
						numPackets	: encoding.source.numPackets,
						numPacketsDelta	: encoding.source.numPacketsDelta,
						numFrames	: encoding.source.numFrames,
						numFramesDelta	: encoding.source.numFramesDelta,
						totalBytes	: encoding.source.totalBytes,
						bitrate		: encoding.source.bitrate,
						layers		: []
					},
					rtx	 : {},
				};
				//Add accumulated bitrate
				this.stats[encoding.id].numPackets	= this.stats[encoding.id].media.numPacketsDelta;
				this.stats[encoding.id].numPacketsDelta	= this.stats[encoding.id].media.numPacketsDelta;
				this.stats[encoding.id].numFrames	= this.stats[encoding.id].media.numFrames;
				this.stats[encoding.id].numFramesDelta	= this.stats[encoding.id].media.numFramesDelta;
				this.stats[encoding.id].bitrate = this.stats[encoding.id].media.bitrate;
				this.stats[encoding.id].total	= this.stats[encoding.id].media.bitrate;
				//Add timestamps
				this.stats[encoding.id].timestamp = Date.now();
				
			}
		}
		
		//Set simulcast index
		let simulcastIdx = 0;
		
		//Order the encodings in reverse order
		for (let stat of Object.values(this.stats).sort((a,b)=>a.bitrate>b.bitrate))
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
	 * @returns {Object} Active layers object containing an array of active and inactive encodings and an array of all available layer info
	 */
	getActiveLayers()
	{
		const active	= [];
		const inactive  = [];
		const all	= [];
		
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
			const encoding = {
				id		: id,
				simulcastIdx	: stats[id].simulcastIdx,
				bitrate		: stats[id].bitrate,
				layers		: []
			};
			
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
				encoding.layers = encoding.layers.sort((a, b) => a.bitrate<b.bitrate);
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
			active		: active.sort((a, b) => a.bitrate<b.bitrate),
			inactive	: inactive, 
			layers		: all.sort((a, b) => a.bitrate<b.bitrate)
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
	 * @returns {Object}
	 */
	getSSRCs()
	{
		const ssrcs = {};
		
		//For each source
		for (let encoding of this.encodings.values())
			//Push new encoding
			ssrcs[encoding.id] = {
				media : encoding.source.media,
				rtx   : encoding.source.rtx,
			};
		//Return the stats array
		return ssrcs;
	}
	
	/**
	* Get track media type
	* @returns {String} "audio"|"video" 
	*/
	getMedia()
	{
		return this.media;
	}
	
	/**
	 * Add event listener
	 * @param {String} event	- Event name 
	 * @param {function} listener	- Event listener
	 * @returns {IncomingStreamTrack} 
	 */
	on() 
	{
		//Delegate event listeners to event emitter
		this.emitter.on.apply(this.emitter, arguments);
		//Return object so it can be chained
		return this;
	}
	
	/**
	 * Add event listener once
	 * @param {String} event	- Event name 
	 * @param {function} listener	- Event listener
	 * @returns {IncomingStream} 
	 */
	once() 
	{
		//Delegate event listeners to event emitter
		this.emitter.once.apply(this.emitter, arguments);
		//Return object so it can be chained
		return this;
	}
	
	/**
	 * Remove event listener
	 * @param {String} event	- Event name 
	 * @param {function} listener	- Event listener
	 * @returns {IncomingStreamTrack} 
	 */
	off() 
	{
		//Delegate event listeners to event emitter
		this.emitter.removeListener.apply(this.emitter, arguments);
		//Return object so it can be chained
		return this;
	}
	
	/**
	 * Get all track encodings
	 * Internal use, you'd beter know what you are doing before calling this method
	 * @returns {Array<Object>} - encodings 
	 **/
	getEncodings()
	{
		return Array.from(this.encodings.values());
	}

	/**
	 * Get encoding by id
	 * Internal use, you'd beter know what you are doing before calling this method
	 * @param {String} encodingId	- encoding Id,
	 * @returns {Object}		- encoding 
	 **/
	getEncoding(encodingId)
	{
		return this.encodings.get(encodingId);
	}
	
	/**
	 * Get default encoding
	 * Internal use, you'd beter know what you are doing before calling this method
	 * @returns {Object}		- encoding 
	 **/
	getDefaultEncoding()
	{
		return this.encodings.values().next().value;
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
			/**
			* IncomingStreamTrack stopped event
			*
			* @name attached
			* @memberof IncomingStreamTrack
			* @kind event
			* @argument {IncomingStreamTrack} incomingStreamTrack
			*/
			this.emitter.emit("attached",this);
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
			/**
			* IncomingStreamTrack stopped event
			*
			* @name detached
			* @memberof IncomingStreamTrack
			* @kind event
			* @argument {IncomingStreamTrack} incomingStreamTrack
			*/
			this.emitter.emit("detached",this);
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
	mute(muting) 
	{
		//For each source
		for (let encoding of this.encodings.values())
		{
			//Mute encoding
			encoding.source.Mute(muting);
			//If unmuting
			if (!muting)
				//Request an iframe on main ssrc
				this.receiver.SendPLI(encoding.source.media.ssrc);
		}
		
		//If we are different
		if (this.muted!==muting)
		{
			//Store it
			this.muted = muting;
			/**
			* IncomingStreamTrack stopped event
			*
			* @name muted
			* @memberof OutgoingStreamTrack
			* @kind event
			* @argument {boolean} muted
			*/
			this.emitter.emit("muted",this.muted);
		}
	}

	/**
	 * Removes the track from the incoming stream and also detaches any attached outgoing track or recorder
	 */
	stop()
	{
		//Don't call it twice
		if (!this.receiver) return;
		
		/**
		* IncomingStreamTrack stopped event
		*
		* @name stopped
		* @memberof IncomingStreamTrack
		* @kind event
		* @argument {IncomingStreamTrack} incomingStreamTrack
		*/
		this.emitter.emit("stopped",this);
		
		//remove encodings
		this.encodings.clear();
		this.depacketizer = null;

		
		//Remove transport reference, so destructor is called on GC
		this.receiver = null;
	}

}

module.exports = IncomingStreamTrackBridge;
