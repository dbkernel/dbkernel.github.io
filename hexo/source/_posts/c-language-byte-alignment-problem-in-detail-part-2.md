---
title: 程序人生 | C语言字节对齐问题详解 - 对齐/字节序/位序/网络序等（下）
date: 2014-07-21 15:35:30
categories:
- C语言
tags:
- C语言
- 字节对齐
- 字节序
- 网络序
toc: true
---

<!-- more -->


# 6. 附录

## 6.1. 字节序与网络序

### 6.1.1. 字节序

**字节序**，顾名思义就是**字节的高低位存放顺序**。

对于单字节，大部分处理器以相同的顺序处理比特位，因此单字节的存放和传输方式一般相同。

对于多字节数据，如整型（32位机中一般占4字节），在不同的处理器的存放方式主要有两种（以内存中 0x0A0B0C0D 的存放方式为例）。

#### 6.1.1.1. 大字节序（Big-Endian，又称大端序或大尾序）

在计算机中，存储介质以下面方式存储整数 0x0A0B0C0D，则称为**大字节序**：
>数据以8bit为单位：
>低地址方向 -> 0x0A 0x0B	0x0C 0x0D -> 高地址方向
>
>数据以16bit为单位：
>低地址方向 -> 0x0A0B 0x0C0D -> 高地址方向

其中，最高有效位(MSB，Most Significant Byte)0x0A存储在最低的内存地址处。下个字节0x0B存在后面的地址处。同时，最高的16bit单元0x0A0B存储在低位。

简而言之，大字节序就是**高字节存入低地址，低字节存入高地址**。

>这里讲个词源典故：“endian”一词来源于乔纳森·斯威夫特的小说《格列佛游记》。小说中，小人国为水煮蛋该从大的一端(Big-End)剥开还是小的一端(Little-End)剥开而争论，争论的双方分别被称为 Big-endians 和 Little-endians 。
>
>1980年，Danny Cohen在其著名的论文"*On Holy Wars and a Plea for Peace*"中为平息一场关于字节该以什么样的顺序传送的争论而引用了该词。

借用上面的典故，想象一下要把熟鸡蛋旋转着稳立起来，大头（高字节）肯定在下面（低地址）^_^

#### 6.1.1.2. 小字节序（Little-Endian，又称小端序或小尾序）

在计算机中，存储介质以下面方式存储整数 0x0A0B0C0D 则称为**小字节序**：
>数据以8bit为单位：
>高地址方向 -> 0x0A 0x0B	0x0C 0x0D -> 低地址方向
>
>数据以16bit为单位：
>高地址方向 -> 0x0A0B 0x0C0D -> 低地址方向

其中，最低有效位(LSB，Least Significant Byte)0x0D存储在最低的内存地址处。后面字节依次存在后面的地址处。同时，最低的16bit单元0x0A0B存储在低位。

可见，小字节序就**高字节存入高地址，低字节存入低地址**。

C语言中的位域结构也要遵循**比特序(类似字节序)** 。例如：

```cpp
struct bitfield{
    unsigned char a: 2;
    unsigned char b: 6;
}
```

**该位域结构占1个字节，假设赋值a=0x01和b=0x02，则大字节机器上该字节为(01)(000010)，小字节机器上该字节为(000010)(01)** 。因此在编写可移植代码时，需要加条件编译。

注意，在包含位域的C结构中，**若位域A在位域B之前定义，则位域A所占用的内存空间地址低于位域B所占用的内存空间**。

另见以下联合体，在小字节机器上若low=0x01，high=0x02，则hex=0x21：

```cpp
int main(void){
    union{
        unsigned char hex;
        struct{
            unsigned char low  : 4;
            unsigned char high : 4;
        };
    }convert;
    convert.low = 0x01;
    convert.high = 0x02;
    printf("hex = 0x%0x\n", convert.hex);
    return 0;
}
```

#### 6.1.1.3. 注意事项

**无论是大字节序，还是小字节序，变量的地址都等于变量所占字节中的低地址。**例如，下述程序中，小字节序输出 0x0D，大字节序输出 0x0A 。
```cpp
 int32_t a = 0x0A0B0C0D;
 printf("0x%0x\n", *((int8_t*)&dwData));
```


### 6.1.2. 网络序

网络传输一般采用**大字节序**，也称为**网络字节序**或**网络序**。IP协议中定义大字节序为网络字节序。

对于可移植的代码来说，将接收的网络数据转换成主机的字节序是必须的，一般会有成对的函数用于把网络数据转换成相应的主机字节序或反之（若主机字节序与网络字节序相同，通常将函数定义为空宏）。

伯克利socket API定义了一组转换函数，用于16和32位整数在网络序和主机字节序之间的转换。`htonl、htons`用于**主机序转换到网络序**；`ntohl、ntohs`用于**网络序转换到本机序**。

注意：在大小字节序转换时，必须考虑待转换数据的长度(如5.1.1节的数据单元)。另外**对于单字符或小于单字符的几个bit数据，是不必转换的**，因为**在机器存储和网络发送的一个字符内的bit位存储顺序是一致的**。

### 6.1.3. 位序

用于描述**串行设备的传输顺序**。**一般硬件传输采用小字节序（先传低位），但I2C协议采用大字节序**。网络协议中只有**数据链路层**的底端会涉及到。

### 6.1.4. 处理器字节序

不同处理器体系的字节序如下所示：

- X86、MOS Technology 6502、Z80、VAX、PDP-11 等处理器为 **Little endian**；
- Motorola 6800、Motorola 68000、PowerPC 970、System/370、SPARC(除V9外) 等处理器为 **Big endian**；
- ARM、PowerPC (除PowerPC 970外)、DEC Alpha，SPARC V9，MIPS，PA-RISC and IA64 等的字节序是**可配置的**。

### 6.1.5. 字节序编程

请看下面的语句：
```cpp
printf("%c\n", *((short*)"AB") >> 8);
```

在大字节序下输出为'A'，小字节序下输出为'B'。

下面的代码可用来判断本地机器字节序：

```cpp
//字节序枚举类型
typedef enum{
    ENDIAN_LITTLE = (INT8U)0X00,
    ENDIAN_BIG    = (INT8U)0X01
}E_ENDIAN_TYPE;

E_ENDIAN_TYPE GetEndianType(VOID)
{
    INT32U dwData = 0x12345678;

    // 取数都从低地址开始访问
    if(0x78 == *((INT8U*)&dwData))
        return ENDIAN_LITTLE;
    else
        return ENDIAN_BIG;
}

//Start of GetEndianTypeTest//
#include <endian.h>
VOID GetEndianTypeTest(VOID)
{
#if _BYTE_ORDER == _LITTLE_ENDIAN
    printf("[%s]<Test Case> Result: %s, EndianType = %s!\n", __FUNCTION__,
           (ENDIAN_LITTLE != GetEndianType()) ? "ERROR" : "OK", "Little");
#elif _BYTE_ORDER == _BIG_ENDIAN
    printf("[%s]<Test Case> Result: %s, EndianType = %s!\n", __FUNCTION__,
           (ENDIAN_BIG != GetEndianType()) ? "ERROR" : "OK", "Big");
#endif
}
//End of GetEndianTypeTest//
```

**在字节序不同的平台间的交换数据时，必须进行转换**。比如对于int类型，大字节序写入文件：

```cpp
int i = 100;
write(fd, &i, sizeof(int));
```

小字节序读出后：

```cpp
int i;
read(fd, &i, sizeof(int));
char buf[sizeof(int)];
memcpy(buf, &i, sizeof(int));
for(i = 0; i < sizeof(int); i++)
{
    int v = buf[sizeof(int) - i - 1];
    buf[sizeof(int) - 1] =  buf[i];
    buf[i] = v;
}
memcpy(&i, buf, sizeof(int));
```

上面仅仅是个例子。在不同平台间即使不存在字节序的问题，也尽量不要直接传递二进制数据。作为可选的方式就是使用文本来交换数据，这样至少可以避免字节序的问题。

很多的加密算法为了追求速度，都会采取字符串和数字之间的转换，在计算完毕后，必须注意字节序的问题，在某些实现中可以见到使用预编译的方式来完成，这样很不方便，如果使用前面的语句来判断，就可以自动适应。

字节序问题不仅影响异种平台间传递数据，还影响诸如读写一些特殊格式文件之类程序的可移植性。此时使用预编译的方式来完成也是一个好办法。

## 6.2. 对齐时的填充字节

代码如下：

```cpp
struct A{
    char  c;
    int   i;
    short s;
};

int main(void){
    struct A a;
    a.c = 1; a.i = 2; a.s = 3;
    printf("sizeof(A)=%d\n", sizeof(struct A));
    return 0;
}
```

执行后输出为sizeof(A)=12。


## 6.3. pragma pack语法说明

```cpp
#pragma pack(n)
#pragma pack(push, 1)
#pragma pack(pop)
```

1）`#pragma pack(n)`

>该指令指定结构和联合成员的紧凑对齐。而一个完整的转换单元的结构和联合的紧凑对齐由`/Zp`选项设置。紧凑对齐用pack编译指示在数据说明层设置。该编译指示在其出现后的第一个结构或者联合声明处生效。该编译指示对定义无效。
>
>当使用`#pragma pack (n)` 时，n 为1、2、4、8或16。第一个结构成员后的每个结构成员都被存储在更小的成员类型或n字节界限内。如果使用无参量的`#pragma pack`，结构成员被紧凑为以`/Zp`指定的值。该缺省`/Zp`紧凑值为`/Zp 8`。

2）编译器也支持以下增强型语法：

```cpp
#pragma  pack( [ [ { push | pop } , ] [identifier, ] ] [ n] )
```

若不同的组件使用 pack编译指示 指定不同的紧凑对齐, 这个语法允许你把程序组件组合为一个单独的转换单元。

带push参量的 pack编译指示 的每次出现将当前的紧凑对齐存储到一个内部编译器堆栈中。编译指示的参量表从左到右读取。如果使用push，则当前紧凑值被存储起来；如果给出一个n值，该值将成为新的紧凑值。若指定一个标识符，即选定一个名称，则该标识符将和这个新的的紧凑值联系起来。

带一个pop参量的 pack编译指示 的每次出现都会检索内部编译器堆栈顶的值，并使该值为新的紧凑对齐值。如果使用pop参量且内部编译器堆栈是空的，则紧凑值为命令行给定的值，并将产生一个警告信息。若使用pop且指定一个n值，该值将成为新的紧凑值。

若使用pop且指定一个标识符，所有存储在堆栈中的值将从栈中删除，直到找到一个匹配的标识符。这个与标识符相关的紧凑值也从栈中移出，并且这个仅在标识符入栈之前存在的紧凑值成为新的紧凑值。如果未找到匹配的标识符, 将使用命令行设置的紧凑值，并且将产生一个一级警告。缺省紧凑对齐为8。

**pack编译指示 的新的增强功能让你在编写头文件时，确保在遇到该头文件的前后的紧凑值是一样的**。

## 6.4. Intel关于内存对齐的说明

以下内容节选自《Intel Architecture 32 Manual》。

字、双字和四字在自然边界上不需要在内存中对齐。（对于字、双字和四字来说，自然边界分别是偶数地址，可以被4整除的地址，和可以被8整除的地址。）

无论如何，为了提高程序的性能，数据结构(尤其是栈)应该尽可能地在自然边界上对齐。原因在于，为了访问未对齐的内存，处理器需要作两次内存访问；然而，对齐的内存访问仅需要一次访问。

一个字或双字操作数跨越了4字节边界，或者一个四字操作数跨越了8字节边界，被认为是未对齐的，从而需要两次总线周期来访问内存。一个字起始地址是奇数但却没有跨越字边界被认为是对齐的，能够在一个总线周期中被访问。

某些操作双四字的指令需要内存操作数在自然边界上对齐。如果操作数没有对齐，这些指令将会产生一个通用保护异常(#GP)。双四字的自然边界是能够被16整除的地址。其他操作双四字的指令允许未对齐的访问(不会产生通用保护异常)，然而，需要额外的内存总线周期来访问内存中未对齐的数据。

## 6.5. 不同架构处理器的对齐要求

**RISC指令集处理器（MIPS/ARM）**：这种处理器的设计以效率为先，要求所访问的多字节数据（short/int/long）的地址必须是此数据大小的倍数，如short数据地址应为2的倍数，long数据地址应为4的倍数，也就是说是对齐的。

**CISC指令集处理器(X86)** ：没有上述限制。

**对齐处理策略**

访问非对齐多字节数据时(pack数据)，编译器会将指令拆成多条(因为非对齐多字节数据可能跨越地址对齐边界)，保证每条指令都从正确的起始地址上获取数据，但也因此效率比较低。

访问对齐数据时则只用一条指令获取数据，因此对齐数据必须确保其起始地址是在对齐边界上。如果不是在对齐的边界，对X86 CPU是安全的，但对MIPS/ARM这种RISC CPU会出现`总线访问异常`。

为什么X86是安全的呢？

>X86 CPU是如何进行数据对齐的？
>
>X86 CPU的`EFLAGS寄存器`中包含一个特殊的位标志，称为`AC`(对齐检查的英文缩写)标志。
>
>按照默认设置，当CPU首次加电时，该标志被设置为0。
>
>当该标志是0时，CPU能够自动执行它应该执行的操作，以便成功地访问未对齐的数据值。
>
>然而，如果该标志被设置为1，每当系统试图访问未对齐的数据时，CPU就会发出一个`INT 17H中断`。
>
>X86的Windows 2000和Windows 98版本从来不改变这个CPU标志位。因此，当应用程序在X86处理器上运行时，你根本看不到应用程序中出现数据未对齐的异常条件。

为什么MIPS/ARM不安全呢？

>**因为MIPS/ARM CPU不能自动处理对未对齐数据的访问**。当未对齐的数据访问发生时，CPU就会将这一情况通知操作系统。这时，操作系统将会确定它是否应该引发一个数据未对齐异常条件，对vxworks是会触发这个异常的。

## 6.6. ARM下的对齐处理

有部分摘自ARM编译器文档对齐部分。

对齐的使用：

1. `__align(num)` 用于修改最高级别对象的字节边界。
>- 在汇编中使用LDRD或STRD时就要用到此命令`__align(8)`进行修饰限制。来保证数据对象是相应对齐。
>- 这个修饰对象的命令最大是8个字节限制，可以让2字节的对象进行4字节对齐，但不能让4字节的对象2字节对齐。
>- `__align`是存储类修改，只修饰最高级类型对象，不能用于结构或者函数对象。

2. `__packed` 进行一字节对齐。需注意：
>- 不能对packed的对象进行对齐；
>- 所有对象的读写访问都进行非对齐访问；
>- float及包含float的结构联合及未用__packed的对象将不能字节对齐；
>- __packed对局部整型变量无影响。
>- 强制由unpacked对象向packed对象转化时未定义。整型指针可以合法定义为packed，如__packed int* p(__packed int 则没有意义)

对齐或非对齐读写访问可能存在的问题：

```cpp
//定义如下结构，b的起始地址不对齐。在栈中访问b可能有问题，因为栈上数据对齐访问
__packed struct STRUCT_TEST{
    char a;
    int  b;
    char c;
};

//将下面的变量定义成全局静态(不在栈上)
static char *p;
static struct STRUCT_TEST a;

void main(){
    __packed int *q; //定义成__packed来修饰当前q指向为非对齐的数据地址下面的访问则可以
    p = (char*)&a;
    q = (int*)(p + 1);
    *q = 0x87654321;

    /* 得到赋值的汇编指令很清楚
    ldr      r5,0x20001590 ; = #0x12345678
    [0xe1a00005]   mov     r0,r5
    [0xeb0000b0]   bl      __rt_uwrite4  //在此处调用一个写4字节的操作函数
    [0xe5c10000]   strb    r0,[r1,#0]    //函数进行4次strb操作然后返回，正确访问数据
    [0xe1a02420]   mov     r2,r0,lsr #8
    [0xe5c12001]   strb    r2,[r1,#1]
    [0xe1a02820]   mov     r2,r0,lsr #16
    [0xe5c12002]   strb    r2,[r1,#2]
    [0xe1a02c20]   mov     r2,r0,lsr #24
    [0xe5c12003]   strb    r2,[r1,#3]
    [0xe1a0f00e]   mov     pc,r14

    若q未加__packed修饰则汇编出来指令如下(会导致奇地址处访问失败)：
    [0xe59f2018]   ldr      r2,0x20001594 ; = #0x87654321
    [0xe5812000]   str     r2,[r1,#0]
    */
    //这样很清楚地看到非对齐访问如何产生错误，以及如何消除非对齐访问带来的问题
    //也可看到非对齐访问和对齐访问的指令差异会导致效率问题
}
```

## 6.7. 《The C Book》之位域篇

While we're on the subject of structures, we might as well look at bitfields. They can only be declared inside a structure or a union, and allow you to specify some very small objects of a given number of bits in length. Their usefulness is limited and they aren't seen in many programs, but we'll deal with them anyway. This example should help to make things clear:

```cpp
struct{
    unsigned field1 :4; //field 4 bits wide
    unsigned        :3; //unnamed 3 bit field(allow for padding)
    signed field2   :1; //one-bit field(can only be 0 or -1 in two's complement)
    unsigned        :0; //align next field on a storage unit
    unsigned field3 :6;
}full_of_fields;
```

Each field is accessed and manipulated as if it were an ordinary member of a structure. The keywords signed and unsigned mean what you would expect, except that it is interesting to note that a 1-bit signed field on a two's complement machine can only take the values 0 or -1. The declarations are permitted to include the const and volatile qualifiers.

The main use of bitfields is either to allow tight packing of data or to be able to specify the fields within some externally produced data files. C gives no guarantee of the ordering of fields within machine words, so if you do use them for the latter reason, you program will not only be non-portable, it will be compiler-dependent too. The Standard says that fields are packed into ‘storage units’, which are typically machine words. The packing order, and whether or not a bitfield may cross a storage unit boundary, are implementation defined. To force alignment to a storage unit boundary, a zero width field is used before the one that you want to have aligned.

Be careful using them. It can require a surprising amount of run-time code to manipulate these things and you can end up using more space than they save.

Bit fields do not have addresses—you can't have pointers to them or arrays of them.

## 6.8. C语言字节相关面试题

### 6.8.1. Intel/微软C语言面试题

请看下面的问题：

```cpp
#pragma pack(8)
struct s1{
    short a; // 按 min(1,8) 对齐
    long  b; // 按 min(4,8) 对齐
};
struct s2{
    char c;
    s1   d;
    long long e;  //VC6.0下可能要用__int64代替双long
};
#pragma pack()
```

**问题：**
1. sizeof(s2) = ？
2. s2的s1中的a后面空了几个字节接着是b？

分析：
>成员对齐有一个重要的条件，即**每个成员分别按自己的方式对齐**。
>
>也就是说上面虽然指定了按8字节对齐，但并不是所有的成员都是以8字节对齐。其对齐的规则是：**每个成员按 `其类型的对齐参数（通常是这个类型的大小）` 和 `指定对齐参数（这里是8字节）` 中较小的一个对齐，并且结构的长度必须为所用过的所有对齐参数的整数倍，不够就补空字节。**
>
>s1中成员a是1字节，默认按1字节对齐，而指定对齐参数为8，两值中取1，即a按1字节对齐；成员b是4个字节，默认按4字节对齐，这时就按4字节对齐，所以`sizeof(s1)应该为8`；
>
>s2中c和s1中a一样，按1字节对齐。而d是个8字节结构体，其默认对齐方式就是所有成员使用的对齐参数中最大的一个，s1的就是4。所以，成员d按4字节对齐。成员e是8个字节，默认按8字节对齐，和指定的一样，所以它对到8字节的边界上。这时，已经使用了12个字节，所以又添加4个字节的空，从第16个字节开始放置成员e。此时长度为24，并可被8（成员e按8字节对齐）整除。这样，一共使用了24个字节。

各个变量在内存中的布局为：
```
c***aa**
bbbb****
dddddddd ——这种“矩阵写法”很方便看出结构体实际大小！
```
因此，`sizeof(S2)结果为24，a后面空了2个字节接着是b`。

这里有三点很重要：

1. 每个成员分别按自己的方式对齐，并能最小化长度；
2. 复杂类型(如结构)的默认对齐方式是其最长的成员的对齐方式，这样在成员是复杂类型时可以最小化长度；
3. 对齐后的长度必须是成员中最大对齐参数的整数倍，这样在处理数组时可保证每一项都边界对齐。

还要注意，“空结构体”(不含数据成员)的大小为1，而不是0。试想如果不占空间的话，一个空结构体变量如何取地址、两个不同的空结构体变量又如何得以区分呢？


### 6.8.2 上海网宿科技面试题

假设硬件平台是intel x86(little endian)，以下程序输出什么：

```cpp
//假设硬件平台是intel x86(little endian)
typedef unsigned int uint32_t;
void inet_ntoa(uint32_t in){
    char  b[18];
    register  char  *p;
    p = (char *)∈
#define UC(b) (((int)b)&0xff) //byte转换为无符号int型
    sprintf(b, "%d.%d.%d.%d\n", UC(p[0]), UC(p[1]), UC(p[2]), UC(p[3]));
    printf(b);
}

int main(void){
    inet_ntoa(0x12345678);
    inet_ntoa(0x87654321);
    return 0;
}
```

先看如下程序：
```cpp
int main(void){
    int a = 0x12345678;
    char *p = (char *)&a;
    char str[20];
    sprintf(str,"%d.%d.%d.%d\n", p[0], p[1], p[2], p[3]);
    printf(str);
    return 0;
}
```

**按照小字节序的规则，变量a在计算机中存储方式为：**
>高地址方向 --------------> 低地址方向
>0x12 0x34 0x56 0x78
>p[3] p[2] p[1] p[0]


注意：**p并不是指向0x12345678的开头0x12，而是指向0x78**。p[0]到p[1]的操作是&p[0]+1，因此p[1]地址比p[0]地址大。输出结果为`120.86.52.18`。

反过来的话，令`int a = 0x87654321`，则输出结果为`33.67.101.-121`。

为什么有负值呢？
>因为系统默认的char是有符号的，本来是0x87也就是135，大于127因此就减去256得到-121。

想要得到正值的话只需将`char *p = (char *)&a`改为`unsigned char *p = (unsigned char *)&a`即可。

综上不难得出，网宿面试题的答案为`120.86.52.18`和`33.67.101.135`。


>**说明：**
>本文转载自 https://www.cnblogs.com/clover-toeic/p/3853132.html


----

欢迎关注我的微信公众号【MySQL数据库技术】。

<img src="https://dbkernel-1306518848.cos.ap-beijing.myqcloud.com/wechat/my-wechat-official-account.png" width="400" height="400" alt="MySQL数据库技术" align="left"/>

| 标题                 | 网址                                                  |
| -------------------- | ----------------------------------------------------- |
| GitHub               | https://dbkernel.github.io                            |
| 知乎                 | https://www.zhihu.com/people/dbkernel/posts           |
| 思否（SegmentFault） | https://segmentfault.com/u/dbkernel                   |
| 掘金                 | https://juejin.im/user/5e9d3ed251882538083fed1f/posts |
| 开源中国（oschina）  | https://my.oschina.net/dbkernel                       |
| 博客园（cnblogs）    | https://www.cnblogs.com/dbkernel                      |

