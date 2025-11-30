for file in destroy/*; do
    if [ -f "$file" ]; then
        swift "$file" 1000000000 &
    fi
done
wait
