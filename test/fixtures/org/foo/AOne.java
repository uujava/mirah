package org.foo;
import static java.awt.Color.*;
 /**
    java doc
 */
public abstract class AOne implements org.foo.AOneX{
    /** values for constants not implemented */
    public static final java.awt.Color CONST = null;
    private int a;
    private static java.lang.String test;
    private int x;
  /** getter and setter for field @x */
    public int x(){ return 0; }
  /** getter and setter for field @x */
    public int x_set(int value){ return 0; }
    public void call(){}
    public int call(int a,java.lang.String b){ return 0; }
    public java.lang.Integer call(int[] a,java.lang.String b){ return null; }
 /** static method */
    public static void call(int[] a){}
 /** @throws RuntimeException */
    public void call(int a,int b){}
 /** constructor */
    public AOne(){}
 /** static method */
    public static void method(){}
    // SYNTHETIC
    // BRIDGE
 /** @throws RuntimeException */
    public void call(int a){}
}