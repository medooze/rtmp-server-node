const { v4: uuidV4 }	= require("uuid");
const Native		= require("./Native");
const Emitter		= require("medooze-event-emitter");
const SharedPointer	= require("./SharedPointer");
const IncomingStreamTrackBridge = require("./IncomingStreamTrackBridge");
const Stream 		= require("./Stream");

//@ts-expect-error
const parseInt = /** @type {(x: number) => number} */ (global.parseInt);

/** @typedef {IncomingStreamTrackBridge.TrackStats} TrackStats */
/** @typedef {{ [trackId: string]: TrackStats }} StreamStats */

/**
 * @typedef {Object} IncomingStreamBridgeEvents
 * @property {(self: IncomingStreamBridge) => void} stopped
 * @property {(config: string) => void} aacconfig aac specific config received
 */

/**
 * The incoming streams represent the recived media stream from a remote peer.
 * @extends {Emitter<IncomingStreamBridgeEvents>}
 */
class IncomingStreamBridge extends Emitter
{
	constructor(
		/** @type {number} */ maxLateOffset,
		/** @type {number} */ maxBufferingTime)
	{
		//Init emitter
		super();
		//Create new id
		this.id = uuidV4();
		
		//Create native bridge
		this.bridge = new Native.IncomingStreamBridge(this, parseInt(maxLateOffset), parseInt(maxBufferingTime));
		
		//Store sources
		this.tracks = /** @type {Map<String, IncomingStreamTrackBridge>} */ (new Map());
		
		//Create audio and video tracks
		this.tracks.set("audio",new IncomingStreamTrackBridge("audio","audio",SharedPointer(this.bridge.GetAudio()), this));
		this.tracks.set("video",new IncomingStreamTrackBridge("video","video",SharedPointer(this.bridge.GetVideo()), this));
		
		//Listen for aac config
		this.onaacconfig = (/** @type {string} */ config)=>{
			this.emit("aacconfig", config);
		};
		
		//Event listeners
		this.onstreamstopped = (/** @type {import("./Stream")} */ stream)=>{
			//If it is the same as ours
			if (this.stream===stream)
				//Dettach
				this.detach();
		};
	}
	
	/**
	 * The media stream id
	 * @returns {String}
	 */
	getId() 
	{
		return this.id;
	}
	
	/**
	 * Get statistics for all tracks in the stream
	 * 
	 * See OutgoingStreamTrack.getStats for information about the stats returned by each track.
	 * 
	 * @returns {{ [trackId: string]: IncomingStreamTrackBridge.TrackStats }}
	 */
	getStats() 
	{
		const stats = /** @type {StreamStats} */ ({});
		
		//for each track
		for (let track of this.tracks.values())
			//Append stats
			stats[track.getId()] = track.getStats();
		
		return stats;
	}
	
	/**
	 * Get statistics for all tracks in the stream
	 * 
	 * See OutgoingStreamTrack.getStats for information about the stats returned by each track.
	 * 
	 * @returns {Promise<{ [trackId: string]: IncomingStreamTrackBridge.TrackStats }>}
	 */
	async getStatsAsync() 
	{
		// construct a list of promises for each [track ID, track stats] entry
		const promises = this.getTracks().map(async track => /** @type {const} */ (
			[ track.getId(), await track.getStatsAsync() ]));

		// wait for all entries to arrive, then assemble the object from the entries
		return Object.fromEntries(await Promise.all(promises));
	}
	
	/**
	 * Get track by id
	 * @param {String} trackId	- The track id
	 * @returns {IncomingStreamTrackBridge | undefined}
	 */
	getTrack(trackId) 
	{
		//get it
		return this.tracks.get(trackId);
	}
	
	/**
	 * Get all the tracks
	* @returns {Array<IncomingStreamTrackBridge>}	- Array of tracks
	 */
	getTracks() 
	{
		//Return a track array
		return Array.from(this.tracks.values());
	}
	/**
	 * Get an array of the media stream audio tracks
	 * @returns {Array<IncomingStreamTrackBridge>}	- Array of tracks
	 */
	getAudioTracks() 
	{
		var audio = /** @type {IncomingStreamTrackBridge[]} */ ([]);
		
		//For each track
		for (let track of this.tracks.values())
			//If it is an video track
			if(track.getMedia().toLowerCase()==="audio")
				//Append to tracks
				audio.push(track);
		//Return all tracks
		return audio;
	}
	
	/**
	 * Get an array of the media stream video tracks
	 * @returns {Array<IncomingStreamTrackBridge>}	- Array of tracks
	 */
	getVideoTracks() 
	{
		var video = /** @type {IncomingStreamTrackBridge[]} */ ([]);
		
		//For each track
		for (let track of this.tracks.values())
			//If it is an video track
			if(track.getMedia().toLowerCase()==="video")
				//Append to tracks
				video.push(track);
		//Return all tracks
		return video;
	}
	
	/** @deprecated */
	dettach()
	{
		return this.detach();
	}

	detach()
	{
		//If we had an stream
		if (this.stream)
		{
			//Remove listener
			this.stream.stream.RemoveMediaListener(this.bridge);
			//Remove listener
			this.stream.off("stopped", this.onstreamstopped);
		}
		//No stream
		this.stream = null;
	}
	
	attachTo(/** @type {import("./Stream") | undefined} */ stream)
	{
		//Dettach just in case
		this.detach();
		
		//If attaching to a stream
		if (stream)
		{
			//Attach
			stream.stream.AddMediaListener(this.bridge);
			//Listen for stopped event
			stream.once("stopped", this.onstreamstopped);
		}
		
		//Store new stream
		this.stream = stream;
	}
	
		
	/**
	 * Removes the media strem from the transport and also detaches from any attached incoming stream
	 */
	stop()
	{
		//Don't call it twice
		if (!this.bridge) return;
		
		//Dettach
		this.detach();
		
		//Stop all streams
		for (let track of this.tracks.values())
			//Stop track
			track.stop();
		
		//Clear tracks jic
		this.tracks.clear();
		
		//Stop bridge
		this.bridge.Stop();
		
		/**
		* IncomingStreamBridge stopped event
		*
		* @name stopped
		* @memberof IncomingStreamBridge
		* @kind event
		* @argument {IncomingStreamBridge} incomingStreamBridge
		*/
		this.emit("stopped", this);
		
		//Stop emitter
		super.stop();
		
		//Remove brdige reference, so destructor is called on GC
		//@ts-expect-error
		this.bridge = null;
	}
}

module.exports = IncomingStreamBridge;
