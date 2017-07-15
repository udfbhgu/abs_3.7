#!/bin/bash
# media calculator exe 

n_iter=5
counter=0
media=0
        
x=0
        
while [ $counter -lt $n_iter ]
do
counter=`expr $counter + 1`
        
x=`./dikh <input_file -p 50 | egrep Running | awk '{printf ($6"\n")}'`
        
echo "x=" $x
        
media=`expr $media + $x`
done
        
media=`expr $media / $n_iter`
done

exit 0