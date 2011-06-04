package {
	import flash.media.Sound;
	import flash.events.SampleDataEvent;
	import flash.display.Sprite;
    import flash.external.ExternalInterface;
    public class XAudioJS extends Sprite {
        public var sound:Sound = null;
		public var bufferingTotal:int = 50000;
        public var buffer:Array = new Array(50000);
		public var resampleBuffer:Array = new Array(16384);
		public var sampleRate:Number = 0;
		public var defaultNeutralLevel:Number = 0;
		public var startPositionOverflow:Number = 0;
		public var resampleAmount:Number = 1;
		public var resampleAmountFloor:int = 1;
		public var resampleAmountRemainder:Number = 0;
		public var startPosition:int = 0;
		public var endPosition:int = 0;
		public var samplesFound:int = 0;
        public function XAudioJS() {
			ExternalInterface.addCallback('writeAudio',  writeAudio);
			ExternalInterface.addCallback('writeAudioNoReturn',  writeAudioNoReturn);
			ExternalInterface.addCallback('remainingSamples',  remainingSamples);
			ExternalInterface.addCallback('initialize',  initialize);
        }
		//Initialization function for the flash backend of XAudioJS:
        public function initialize(sampleRate:Number, bufferingTotal:Number, defaultNeutralLevel:Number):void {
			//Initialize the new settings:
			this.sampleRate = sampleRate;
			this.bufferingTotal = int(bufferingTotal);
			this.buffer = new Array(this.bufferingTotal);
			this.defaultNeutralLevel = defaultNeutralLevel;
			this.resetBuffer();
			this.initializeResampling();
			this.checkForSound();
		}
		//Reset the audio ring buffer:
		public function resetBuffer():void {
			this.startPosition = 0;
			this.endPosition = 0;
		}
		//Initialize some variables for the resampler:
		public function initializeResampling():void {
			//Pre-calculate some resampling algorithm variables:
			this.resampleAmount = this.sampleRate / 44100;
			this.resampleAmountFloor = int(this.resampleAmount);
			this.resampleAmountRemainder = this.resampleAmount - Number(this.resampleAmountFloor);
			this.startPositionOverflow = 0;
		}
		//Audio resampling:
		public function resample():void {
			if (this.sampleRate > 44100) {
				//Downsampler:
				var sampleBase1:Number = 0;
				var sampleBase2:Number = 0;
				var sampleIndice:Number = 1;
				for (this.samplesFound = 0; this.samplesFound < 16384 && this.startPosition != this.endPosition;) {
					sampleBase1 = this.buffer[this.startPosition++];
					sampleBase2 = this.buffer[this.startPosition++];
					if (this.startPosition == this.endPosition) {
						break;
					}
					if (this.startPosition == this.bufferingTotal) {
						this.startPosition = 0;
					}
					for (sampleIndice = 1; sampleIndice < this.resampleAmountFloor; sampleIndice++) {
						sampleBase1 += this.buffer[this.startPosition++];
						sampleBase2 += this.buffer[this.startPosition++];
						if (this.startPosition == this.endPosition) {
							//Revert the position counter:
							this.startPosition -= sampleIndice << 1;
							if (this.startPosition < 0) {
								this.startPosition += this.bufferingTotal;
							}
							return;
						}
						if (this.startPosition == this.bufferingTotal) {
							this.startPosition = 0;
						}
					}
					this.startPositionOverflow += this.resampleAmountRemainder;
					if (this.startPositionOverflow >= 1) {
						this.startPositionOverflow--;
						sampleBase1 += this.buffer[this.startPosition++];
						sampleBase2 += this.buffer[this.startPosition++];
						if (this.startPosition == this.bufferingTotal) {
							this.startPosition = 0;
						}
						sampleIndice++;
					}
					this.resampleBuffer[this.samplesFound++] = sampleBase1 / sampleIndice;
					this.resampleBuffer[this.samplesFound++] = sampleBase2 / sampleIndice;
				}
			}
			else if (this.sampleRate < 44100) {
				//Upsampler:
				for (this.samplesFound = 0; this.samplesFound < 16384 && this.startPosition != this.endPosition;) {
					this.resampleBuffer[this.samplesFound++] = this.buffer[this.startPosition];
					this.resampleBuffer[this.samplesFound++] = this.buffer[this.startPosition + 1];
					this.startPositionOverflow += this.resampleAmount;
					if (this.startPositionOverflow >= 1) {
						--this.startPositionOverflow;
						this.startPosition += 2;
						if (this.startPosition == this.bufferingTotal) {
							this.startPosition = 0;
						}
					}
				}
			}
			else {
				//No resampling:
				for (this.samplesFound = 0; this.samplesFound < 16384 && this.startPosition != this.endPosition;) {
					this.resampleBuffer[this.samplesFound++] = this.buffer[this.startPosition++];
					this.resampleBuffer[this.samplesFound++] = this.buffer[this.startPosition++];
					if (this.startPosition == this.bufferingTotal) {
						this.startPosition = 0;
					}
				}
			}
		}
		//Insert the audio samples into the ring buffer while returning the current samples left:
        public function writeAudio(bufferPassed:String):Number {
			this.addSamples(bufferPassed.split(" "));
			this.checkForSound();
			return this.remainingSamples();
        }
		//Insert the audio samples into the ring buffer without returning the current samples left:
		public function writeAudioNoReturn(bufferPassed:String):void {
			this.addSamples(bufferPassed.split(" "));
			this.checkForSound();
        }
		//Add samples into the audio ring buffer:
		public function addSamples(bufferPassed:Array):void {
			var length:int = bufferPassed.length;
			if ((length % 2) == 0) {	//Outsmart bad programmers from messing us up. :/
				for (var index:int = 0; index < length;) {
					this.buffer[this.endPosition++] = (Number(bufferPassed[index++]) / 0x8000);
					this.buffer[this.endPosition++] = (Number(bufferPassed[index++]) / 0x8000);
					if (this.endPosition == this.bufferingTotal) {
						this.endPosition = 0;
					}
					if (this.endPosition == this.startPosition) {
						this.startPosition += 2;
						if (this.startPosition == this.bufferingTotal) {
							this.startPosition = 0;
						}
					}
				}
			}
        }
		//Check to make sure the audio stream is enabled:
		public function checkForSound():void {
			if (this.sound == null) {
				this.sound = new Sound(); 
				this.sound.addEventListener(
					SampleDataEvent.SAMPLE_DATA,
					soundCallback
				);
				this.sound.play();
            }
		}
		//Return the number of samples left in the audio ring buffer:
		public function remainingSamples():Number {
			if (this.endPosition < this.startPosition) {
				return Number(this.endPosition - this.startPosition + this.bufferingTotal);
			}
			return Number(this.endPosition - this.startPosition);
		}
		//Flash Audio Refill Callback
        public function soundCallback(e:SampleDataEvent):void {
			var index:int = 0;
			if (this.startPosition != this.endPosition) {
				this.resample();
				while (index < this.samplesFound) {
					e.data.writeFloat(this.resampleBuffer[index++]);
					e.data.writeFloat(this.resampleBuffer[index++]);
				}
			}
			while (index < 4096) {
				e.data.writeFloat(this.defaultNeutralLevel);
				e.data.writeFloat(this.defaultNeutralLevel);
				index += 2;
			}
        }
    }
}