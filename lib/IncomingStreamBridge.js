const uuidV4		= require("uuid/v4");
const Native		= require("./Native");
const Emitter		= require("./Emitter");
const IncomingStreamTrackBrige = require("./IncomingStreamTrackBridge");


/**
 * The incoming streams represent the recived media stream from a remote peer.
 */
class IncomingStreamBridge extends Emitter
{
	/**
	 * @ignore
	 * @hideconstructor
	 * private constructor
	 */
	constructor()
	{
		//Init emitter
		super();
		//Create new id
		this.id = uuidV4();
		
		//Create native bridge
		this.bridge = new Native.IncomingStreamBridge();
		
		//Store sources
		this.tracks = new Map();
		
		//Create audio and video tracks
		this.tracks.set("audio",new IncomingStreamTrackBrige("audio","audio",this.bridge.GetReceiver(),[this.bridge.GetAudio()]));
		this.tracks.set("video",new IncomingStreamTrackBrige("video","video",this.bridge.GetReceiver(),[this.bridge.GetVideo()]));
		
		//Event listeners
		this.onstreamstopped = (stream)=>{
			//If it is the same as ours
			if (this.stream===stream)
				//Dettach
				this.dettach();	
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
	 * Get track by id
	 * @param {String} trackId	- The track id
	 * @returns {IncomingStreamTrack}	- requested track or null
	 */
	getTrack(trackId) 
	{
		//get it
		return this.tracks.get(trackId);
	}
	
	/**
	 * Get all the tracks
	* @returns {Array<IncomingStreamTrack>}	- Array of tracks
	 */
	getTracks() 
	{
		//Return a track array
		return Array.from(this.tracks.values());
	}
	/**
	 * Get an array of the media stream audio tracks
	 * @returns {Array<IncomingStreamTrack>}	- Array of tracks
	 */
	getAudioTracks() 
	{
		var audio = [];
		
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
	 * @returns {Array<IncomingStreamTrack>}	- Array of tracks
	 */
	getVideoTracks() 
	{
		var video = [];
		
		//For each track
		for (let track of this.tracks.values())
			//If it is an video track
			if(track.getMedia().toLowerCase()==="video")
				//Append to tracks
				video.push(track);
		//Return all tracks
		return video;
	}
	
	dettach()
	{
		//If we had an stream
		if (this.stream)
		{
			//Remove listener
			this.stream.stream.AddMediaListener(this.bridge);
			//Remove listener
			this.stream.off("stopped", this.onstreamstopped);
		}
		//No stream
		this.stream = null;
	}
	
	attachTo(stream)
	{
		//Dettach just in case
		this.dettach();
		
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
		this.dettach();
		
		//Stop all streams
		for (let track of this.tracks.values())
			//Stop track
			track.stop();
		
		//Clear tracks jic
		this.tracks.clear();
		
		/**
		* IncomingStream stopped event
		*
		* @name stopped
		* @memberof IncomingStream
		* @kind event
		* @argument {IncomingStream} incomingStream
		*/
		this.emitter.emit("stopped", this);
		
		//Stop emitter
		super.stop();
		
		//Remove brdige reference, so destructor is called on GC
		this.bridge = null;
	}
}

module.exports = IncomingStreamBridge;
