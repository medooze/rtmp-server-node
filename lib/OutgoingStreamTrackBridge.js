const Native		= require("./Native");
const SharedPointer	= require("./SharedPointer");
const Emitter		= require("medooze-event-emitter");

/**
 * @typedef {Object} OutgoingStreamTrackBridgeEvents
 * @property {(self: OutgoingStreamTrackBridge) => void} stopped
 */


/**
 * @extends {Emitter<OutgoingStreamTrackBridgeEvents>}
 */
class OutgoingStreamTrackBridge extends Emitter
{
	/**
	 * @ignore
	 * @hideconstructor
	 * private constructor
	 */
	constructor(
		/** @type {"audio" | "video"} */ media,
		/** @type {string} */ id,
		/** @type {SharedPointer.Proxy<Native.MediaFrameListenerShared>} */ mediaFrameListener
		)
	{
		//Init emitter
		super();
		//Store properties
		this.media = media;
		this.id = id;
		this.mediaFrameListener = mediaFrameListener;

		this.onAttachedTrackStopped = (track)=>{
			if (track==this.attached)
				this.attached = null;
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
	 * The media type
	 * @returns {String}
	 */
	getMedia() 
	{
		return this.media;
	}
	
	
	detach()
	{
		//If attached to a decoder
		if (this.attached)
		{
			//Remove event listener
			this.attached.off("stopped", this.onAttachedTrackStopped);

			//Stop listening to media frames from the default depacketizer
			this.attached.depacketizer.RemoveMediaListener(this.mediaFrameListener);
			
		}
		//Not attached
		this.attached = null;
	}
	
	attachTo(track)
	{
		//Detach first
		this.detach();
		
		//Check if valid object
		if (track)
		{
			//Start listening to media frames from the default depacketizer
			track.depacketizer.AddMediaListener(this.mediaFrameListener);
			
			//Detach if incoming stream is stopped
			track.once("stopped", this.onAttachedTrackStopped);

			//Keep attached object
			this.attached = track;
		}
	}
	
	stop()
	{
		//Check not already stopped
		if (this.stopped)
			//Done
			return;

		//Remove us as listener
		this.stopped = true;
		
		//Detach first
		this.detach();
		
		/**
		* OutgoingStreamTrackBridge stopped event
		*
		* @name stopped
		* @memberof OutgoingStreamTrackBridge
		* @kind event
		* @argument {OutgoingStreamTrackBridge} outgoingStreamTrack
		*/
		this.emit("stopped", this);
		
		//Stop emitter
		super.stop();
		
		//Remove native refs
		//@ts-expect-error
		this.mediaFrameListener = null;
	}
};

module.exports = OutgoingStreamTrackBridge;
