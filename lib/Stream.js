const Emitter			= require("medooze-event-emitter");
const Status			= require("./Status");
const IncomingStreamBridge	= require("./IncomingStreamBridge");
const Native			= require("./Native");

/**
 * @typedef {unknown} AMFData
 * a serialized AMF value (see toJson in C++ code)
 */

/**
 * @typedef {Object} Command
 * @property {string} name
 * @property {AMFData} params
 */

/**
 * @typedef {Object} StreamEvents
 * @property {(self: Stream) => void} stopped
 * @property {(cmd: Command, transId: number, ...extra: AMFData[]) => void} cmd
 */

/** @extends {Emitter<StreamEvents>} */
class Stream extends Emitter
{
	constructor(/** @type {Native.RTMPNetStreamImpl} */ stream)
	{
		//Intit emitted
		super();
		
		//Store props
		this.id = 0; //stream.GetId();
		this.stream = stream;
		
		//On command listener
		this.oncmd = (
			/** @type {string} */ name,
			/** @type {AMFData} */ params,
			/** @type {number} */ transId,
			/** @type {AMFData[]} */ ...extra
		) => {
			//Launch async so we can set listeners safely
			setInmediate(()=>{
				try 
				{
					//If not ended already
					if (this.stream)
						//Emit event
						this.emit("cmd",{
							name	: name,
							params	: params
						},transId,...extra);
				} catch(e){
					//Ignore
				}
			});
		};
		//On stopp event (deleteStream net command)
		this.onstopped = ()=>{
			//Stop us
			this.stop();
		};
		
		//Add us as listener
		this.stream.SetListener(this);
	}
	
	getId()
	{
		return this.id;
	}

	getRTT()
	{
		return this.stream.GetRTT();
	}
	
	sendStatus(
		/** @type {number} */ transId,
		/** @type {import("./Status").Status} */ status,
		/** @type {string | undefined} */ desc = undefined)
	{
		//Send it
		this.stream.SendStatus(transId,status.code,status.level,desc || status.code);
	}
	
	createIncomingStreamBridge(
		/** @type {number | undefined} */ maxLateOffset = undefined,
		/** @type {number | undefined} */ maxBufferingTime = undefined)
	{
		if (maxLateOffset === undefined) maxLateOffset = 200;
		if (maxBufferingTime === undefined) maxBufferingTime = 600;

		if (maxLateOffset<0)
			throw Error("maxLateOffset can't be negative");
		if (maxBufferingTime<0)
			throw Error("maxBufferingTime can't be negative");
		if (maxLateOffset>1000)
			throw Error("maxLateOffset can't be higher than 1000");
		if (maxBufferingTime>1000)
			throw Error("maxBufferingTime can't be higher than 1000");

		const bridge = new IncomingStreamBridge(maxLateOffset, maxBufferingTime);
		bridge.attachTo(this);
		return bridge;
	}
	
	stop()
	{
		//Check not already stopped
		if (!this.stream)
			//Done
			return;
		
		//Remove us as listener
		this.stream.ResetListener();
		
		this.emit("stopped", this);
		
		//Stop stream
		this.stream.Stop();
		
		//Stop emitter
		super.stop();
		
		//Stop listener
		//@ts-expect-error
		this.stream = null;
	}
}

module.exports = Stream;
