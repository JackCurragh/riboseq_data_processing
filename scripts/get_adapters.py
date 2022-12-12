import argparse
import subprocess


def rev_comp(adapter):
    '''
    Return the reverse complimnet of a provided nucleotide adapter sequence 
    '''
    adapter = adapter[::-1]
    adapter = (
        adapter.replace("A", "t").replace("T", "a").replace("G", "c").replace("C", "g")
    )
    return adapter.upper()


def get_number_of_reads(fastq_path):
    '''
    return the number of reads in the fastq file (num lines / 4)
    '''
    fastq_lines_output = subprocess.check_output(
        f"wc -l {fastq_path}", shell=True
    )
    fastq_lines = float(fastq_lines_output.split()[0])
    number_of_reads = int(round(fastq_lines/4, 0))
    return number_of_reads


def check_adapter(adapter, fastq_path, number_of_reads=2000000, verbose=False):
    '''
    For a given adapter sequence check for its presence in the given FASTQ file 
    '''
    try:
        if fastq_path.split('.')[-1] == 'gz': 
            adapter_count_raw = subprocess.check_output(
                f"gzip -cd {fastq_path} | head -{number_of_reads} | sed -n '2~4p' > ~/test.fq; agrep -c1 \"{adapter}\" ~/test.fq",
                shell=True, 
            )
        elif fastq_path.split('.')[-1] == 'fastq' or fastq_path.split('.')[-1] == 'fq':
            adapter_count_raw = subprocess.check_output(
                f"head -{number_of_reads} {fastq_path} | sed -n '2~4p' > ~/test.fq; agrep -c1 \"{adapter}\" ~/test.fq",
                shell=True,
            )

    except subprocess.CalledProcessError as e: # When agrep finds no cases it returns with code 1 but 0 is a valid resuly 
        adapter_count_raw = e.output
        # raise RuntimeError(f"command {e.cmd} return with error (code {e.returncode}): {e.output}")

    adapter_count = float(adapter_count_raw.decode('utf-8').strip('\n'))

    percentage_contamination = float((adapter_count / number_of_reads) * 100)

    if percentage_contamination >= (0.05):
        return True
    else:
        return False


def get_adapters(fastq_path, adapter_sequences, verbose=False):
    '''
    Given a list of know adapters check if each (or its reverse compliment) is found in the fastq file for which the path was provided
    '''
    found_adapters ={'forward': [], 'reverse': []}
    number_of_reads = get_number_of_reads(fastq_path)

    for adapter in adapter_sequences:
        verdict = check_adapter(adapter, fastq_path, number_of_reads, verbose=verbose)
        if verdict:
            found_adapters['forward'].append(adapter)

        else:
            adapter = rev_comp(adapter)
            verdict = check_adapter(adapter, fastq_path, number_of_reads, verbose=verbose)
            if verdict:
                found_adapters['reverse'].append(adapter)

    return found_adapters
  

def write_adapter_report(found_adapters, outfile_path):
    '''
    write a simple output file that lists the found forward and reverse adapters 
    '''
    with open(outfile_path, 'w') as outfile:

        for direction in found_adapters:
            for adapter in found_adapters[direction]:
                outfile.write(f'>{direction}\n{adapter}\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()

    parser.add_argument("-q", help="path to fastq file")
    parser.add_argument("-o", help="output path for the report")

    args = parser.parse_args()

    path_list = args.q.split('/')
    fastq_dir = '/'.join(path_list[:-1])
    fastq_filename = path_list[-1]

    adapter_sequences = [
    "CTGTAGGCACCATCAAT",
    "AGATCGGAAGAGC",
    "CGCCTTGGCCGTACAGCAG",
    "AAAAAAAAAAAAA",
    "TGGAATTCTCGGGTGCCAAGG",
    "CCTTGGCACCCGAGAATT",
    "GATCGGAAGAGCGTCGT",
    "CTGATGGCGCGAGGGAG",
    "GATCGGAAGAGCACACG",
    "AATGATACGGCGACCAC",
    "GATCGGAAGAGCTCGTA",
    "CAAGCAGAAGACGGCAT",
    "ACACTCTTTCCCTACA",
    "GATCGGAAGAGCGGTT",
    "ACAGGTTCAGAGTTCTA",
    "CAAGCAGAAGACGGCAT",
    "ACAGGTTCAGAGTTCTA",
    "CAAGCAGAAGACGGCAT",
    "TGATCGGAAGAGCACAC",
    "GATCGGAAGAGCACACGT",
    ]


    found_adapters = get_adapters(fastq_path=args.q, adapter_sequences=adapter_sequences)

    report_path = args.o
    write_adapter_report(found_adapters, report_path)
