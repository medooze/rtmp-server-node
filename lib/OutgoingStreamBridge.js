const { v4: uuidV4 }	= require("uuid");
const Native		= require("./Native");
const Emitter		= require("medooze-event-emitter");
const SharedPointer	= require("./SharedPointer");
const OutgoingStreamTrackBridge = require("./OutgoingStreamTrackBridge.js")

/** @typedef {OutgoingStreamTrackBridge.TrackStats} TrackStats */
/** @typedef {{ [trackId: string]: TrackStats }} StreamStats */

/**
 * @typedef {Object} OutgoingStreamBridgeEvents
 * @property {(self: OutgoingStreamBridge, name: string, cmd: any[]) => void} cmd
 * @property {(self: OutgoingStreamBridge) => void} stopped
 */

/**
 * The outpiging streams represent the sent media stream to a remote peer.
 * @extends {Emitter<OutgoingStreamBridgeEvents>}
 */
class OutgoingStreamBridge extends Emitter
{
	constructor(
		/** @type {number} */ streamId,
		/** @type {number} */ listener)
	{
		//Init emitter
		super();
		//Create new id
		this.id = uuidV4();
		
		//Create native bridge
		this.bridge = SharedPointer(new Native.OutgoingStreamBridgeShared(streamId, listener));
		
		//Store sources
		this.tracks = /** @type {Map<String, OutgoingStreamTrackBridge>} */ (new Map());
		
		//Create audio and video tracks
		this.tracks.set("audio",new OutgoingStreamTrackBridge("audio","audio",SharedPointer(this.bridge.toMediaFrameListener())));
		this.tracks.set("video",new OutgoingStreamTrackBridge("video","video",SharedPointer(this.bridge.toMediaFrameListener())));
		
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
	 * @returns {StreamStats}
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
	 * @returns {Promise<StreamStats>}
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
	 * @returns {OutgoingStreamTrackBridge | undefined}
	 */
	getTrack(trackId) 
	{
		//get it
		return this.tracks.get(trackId);
	}
	
	/**
	 * Get all the tracks
	* @returns {Array<OutgoingStreamTrackBridge>}	- Array of tracks
	 */
	getTracks() 
	{
		//Return a track array
		return Array.from(this.tracks.values());
	}
	/**
	 * Get an array of the media stream audio tracks
	 * @returns {Array<OutgoingStreamTrackBridge>}	- Array of tracks
	 */
	getAudioTracks() 
	{
		var audio = /** @type {OutgoingStreamTrackBridge[]} */ ([]);
		
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
	 * @returns {Array<OutgoingStreamTrackBridge>}	- Array of tracks
	 */
	getVideoTracks() 
	{
		var video = /** @type {OutgoingStreamTrackBridge[]} */ ([]);
		
		//For each track
		for (let track of this.tracks.values())
			//If it is an video track
			if(track.getMedia().toLowerCase()==="video")
				//Append to tracks
				video.push(track);
		//Return all tracks
		return video;
	}
	
	attachTo(incomingStream)
	{
		//Dettach
		this.detach();
		
		//Get all of our audio streams
		const audio = this.getAudioTracks();
		
		//If we have any
		if (audio.length)
		{
			//Get incoming audiotracks
			const tracks = incomingStream.getAudioTracks();
			//Try to match each ones
			for (let i=0; i<audio.length && i<tracks.length; ++i)
				//Attach them
				audio[i].attachTo(tracks[i]);
		}
		
		//Get all of our audio streams
		const video = this.getVideoTracks();
		
		//If we have any
		if (video.length)
		{
			//Get incoming audiotracks
			const tracks = incomingStream.getVideoTracks();
			//Try to match each ones
			for (let i=0; i<video.length && i<tracks.length; ++i)
				//Attach them and get transponder
				video[i].attachTo(tracks[i]);
		}
	}
	
	/**
	 * Stop listening for media 
	 */
	detach()
	{
		//For each track
		for (let track of this.tracks.values())
			//Detach it
			track.detach();
	}

		
	/**
	 * Removes the media strem from the transport and also detaches from any attached incoming stream
	 */
	stop()
	{
		//Check not already stopped
		if (this.stopped)
			//Done
			return;

		//Remove us as listener
		this.stopped = true;
		
		//Stop all streams
		for (let track of this.tracks.values())
			//Stop track
			track.stop();
		
		//Clear tracks jic
		this.tracks.clear();
		
		//Stop bridge
		this.bridge.Stop();
		
		/**
		* OutgoingStreamBridge stopped event
		*
		* @name stopped
		* @memberof OutgoingStreamBridge
		* @kind event
		* @argument {OutgoingStreamBridge} OutgoingStreamBridge
		*/
		this.emit("stopped", this);
		
		//Stop emitter
		super.stop();
		
		//Remove brdige reference, so destructor is called on GC
		//@ts-expect-error
		this.bridge = null;
	}
}

module.exports = OutgoingStreamBridge;
