package org.foo

 /**
    java doc
 */
abstract class AOne implements AOneX
  CONST = 1

  /** getter and setter for field @x */
  attr_accessor x: int

  def call:void;end

  def call(a:int, b:String):int
    @a = 1
  end

  def call(a:int[], b:String):Integer
    1
  end
 /** static method */
  def self.call(a:int[]):void;end

 /** @throws RuntimeException */
  def call(a:int, b:int=1):void;end

 /** constructor */
  def initialize;end

  class << self
    def initialize
      @@test = "x"
    end
 /** static method */
    def method;end
  end
end

interface AOneX < Runnable
end