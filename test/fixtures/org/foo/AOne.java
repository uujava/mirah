package org.foo;
 /**
    java doc
 */
public class AOne {
    /** values for constants not implemented */
    public static final int CONST = 0;
    private int a;
    private static java.lang.String test;
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