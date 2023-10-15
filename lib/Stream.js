const Emitter			= require("medooze-event-emitter");
const Status			= require("./Status");
const IncomingStreamBridge	= require("./IncomingStreamBridge")


class Stream extends Emitter
{
	constructor(stream)
	{
		//Intit emitted
		super();
		
		//Store props
		this.id = 0; //stream.GetId();
		this.stream = stream;
		
		//On command listener
		this.oncmd = (name,params,...extra) => {
			//Launch async so we can set listeners safely
			setTimeout(()=>{
				try 
				{
					//If not ended already
					if (this.stream)
						//Emit event
						this.emit("cmd",{
							name	: name,
							params	: params
						},...extra);
				} catch(e){
					//Ignore
				}
			},0);
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
	
	sendStatus(transId, status,desc)
	{
		//Send it
		this.stream.SendStatus(transId,status.code,status.level,desc || status.code);
	}
	
	createIncomingStreamBridge(maxLateOffset, maxBufferingTime)
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

		return new IncomingStreamBridge(this.stream, maxLateOffset, maxBufferingTime);
	}
	
	stop()
	{
		//Check not already stopped
		if (!this.stream)
			//Done
			return;
		
		//Remove us as listener
		this.stream.ResetListener();
		
		/**
		* IncomingStream stopped event
		*
		* @name stopped
		* @memberof IncomingStream
		* @kind event
		* @argument {IncomingStream} incomingStream
		*/
		this.emit("stopped", this);
		
		//Stop stream
		this.stream.Stop();
		
		//Stop emitter
		super.stop();
		
		//Stop listener
		this.stream = null;
	}
}

module.exports = Stream;
